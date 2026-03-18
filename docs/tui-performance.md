# TUI Rendering Performance

This document covers the performance techniques used in elm-pages TUI scripts,
sourced from studying lazygit, tcell, gocui, and Bubble Tea. It includes what
worked, what didn't, and why.

## Architecture Overview

The elm-pages TUI runs a BackendTask-based event loop:

```
Elm (update model) → JSON encode → JS port → render to terminal → wait for event
     ↑                                                                    │
     └────────────── JSON decode ← JS port ← stdin event ────────────────┘
```

Each cycle is one BackendTask round-trip (~1-5ms). The optimizations below
minimize what happens inside that loop and reduce how many loops are needed.

## Research Sources

- **tcell** (Go terminal library, used by lazygit via gocui):
  https://github.com/gdamore/tcell
  - Cell-level diffing: `tscreen.go` `draw()` — iterates all cells, skips clean ones
  - SGR state tracking: `tscreen.go` `curstyle` — only emits style escape codes on change
  - Synchronized output: `tscreen.go` `startBuffering()`/`endBuffering()` — DEC mode 2026
  - Single write syscall: `bytes.Buffer` accumulates entire frame, one `WriteTo(tty)`
  - No scroll regions: deliberately absent from terminfo struct

- **gocui** (lazygit's TUI framework):
  https://github.com/jesseduffield/gocui
  - Event drain: `gui.go` `processRemainingEvents()` — non-blocking `select` drains channels
  - Layout before draw: `flush()` calls Layout → draw → `Screen.Show()`

- **Bubble Tea** (charmbracelet):
  https://github.com/charmbracelet/bubbletea
  - 60fps renderer cap: `standardRenderer` ticker at ~16.6ms
  - Line-level diffing: splits old/new output by `\n`, skips unchanged lines
  - v1.x cellbuf: cell-level diffing with minimal SGR diff sequences

## Optimizations Applied (in order of impact)

### 1. Multi-sequence parsing from stdin chunks (THE BIG ONE)

**Impact:** Critical — this is what brought scrolling to lazygit-level smoothness

Terminal emulators (especially iTerm2 during fast trackpad scrolling) pack
multiple escape sequences into a single stdin data chunk. For example, a fast
scroll gesture might produce:

```
\x1b[<65;10;5M\x1b[<65;10;5M\x1b[<65;10;5M
```

That's three scroll-down events in one `data` callback. The original parser
used `^...$` regex anchors and only matched if the ENTIRE string was one
sequence. The extra sequences were **silently dropped**.

The fix: `tuiParseAllEvents()` iterates through the chunk, parsing each
sequence via `tuiParseSingleEvent()` which returns `{ event, remaining }`.
Additional events beyond the first are pushed into the persistent event queue.

This means a fast trackpad swipe that generates 10 escape sequences in one
chunk now correctly produces 10 events, all processed through update before
a single render. Previously only 1 of those 10 was captured.

**Why this matters so much:** Terminal scroll "acceleration" is implemented by
the terminal emulator sending MORE escape sequences per OS scroll event, not
by increasing any delta value. iTerm2 applies exponential acceleration:
`result = pow(fabs(delta), factor)` and loops to send that many sequences.
When we dropped most of them, scrolling felt sluggish because only ~10-20% of
the intended scroll distance was actually applied.

### 2. Persistent event queue

**Impact:** High — natural event batching with zero added latency

The stdin listener stays active permanently (set up once in `tuiInit`).
Events arriving while Elm is processing get queued in `tuiEventQueue`.
When the next `tuiWaitEvent` is called:
- Queue has events → resolve immediately with ALL of them (natural batch)
- Queue empty → wait normally (zero added latency for single events)

This is gocui's `processRemainingEvents()` pattern adapted for Node.js.

**Why this works better than setImmediate:** We tried `setImmediate` to
defer resolution and collect events. It added ~1ms latency to EVERY event
(even single ones) because Node.js always defers to the next tick. The
persistent queue approach has zero overhead for single events and naturally
batches when events arrive during Elm processing.

### 3. Combined render+wait request

**Impact:** High — halved per-frame latency

Single `tui-render-and-wait` BackendTask instead of separate render + wait.
Before: 2 round-trips per frame. After: 1.

### 4. 60fps render throttle

**Impact:** Medium-High — especially on slow displays (e-ink)

Skip renders closer than 16ms apart. A deferred render (via `setTimeout`)
ensures the final frame always displays within 16ms of the last event.

This matches Bubble Tea's renderer architecture: events are processed
immediately through update, but terminal writes are rate-limited. Rapid
scrolling produces many model updates but only ~60 actual screen refreshes
per second.

### 5. Cell-level diffing

**Impact:** High — dramatically reduces terminal write size

JS renderer maintains two flat cell buffers (`tuiCurrCells` / `tuiPrevCells`),
each sized to `width × height`. Each cell stores a character and its
pre-computed SGR attribute string. On each frame:

1. `tuiFillCells()` clears the current buffer to spaces, then fills it
   from Elm's span-based screen data (iterating codepoints, not bytes)
2. `tuiFlushCells()` walks both buffers cell-by-cell, emitting escape
   sequences only for cells where `curr.ch !== prev.ch || curr.sgr !== prev.sgr`

Three sub-optimizations inside the flush loop (all from tcell/ratatui):
- **Skip unchanged cells** — the core win. A scroll that moves the highlight
  one row only rewrites the ~40 cells that changed, not the full screen.
- **Cursor position caching** — tracks the implicit cursor position after
  each write. Adjacent dirty cells need zero cursor movement (the cursor
  auto-advances). Small same-row gaps use CUF (relative forward) instead
  of CUP (absolute positioning).
- **SGR state caching** — tracks the currently active SGR string on the
  terminal. Adjacent dirty cells with the same style skip all SGR output.
  Style changes use separate reset + apply sequences (`\x1b[0m` then
  `\x1b[${sgr}m`) to avoid parser issues with 256-color sub-parameters.

Previously this was line-level diffing (compare rendered line strings,
rewrite entire lines + EL on change). Cell-level is strictly better:
changing one character in a status bar rewrites ~15 bytes instead of ~200+.

Source: tcell `drawCell()` in `tscreen.go`, ratatui `BufferDiff` in `diff.rs`.

### 6. Synchronized output (DEC mode 2026)

**Impact:** Medium — eliminates flicker

Frame writes wrapped in `\x1b[?2026h` / `\x1b[?2026l`. The terminal holds
display updates until the frame is complete, then swaps atomically.

Source: tcell `startBuffering()`/`endBuffering()`.
Supported by: kitty, iTerm2, WezTerm, ghostty, Windows Terminal, foot.
Harmless no-op on unsupported terminals.

### 7. SGR state tracking

**Impact:** Low-Medium — reduces escape code overhead

Only emit style escape codes when the style changes between adjacent cells.
The cell-level flush loop tracks `cSgr` (the currently active SGR string
on the terminal) and skips emission entirely when the next dirty cell has
the same style. Style transitions use separate `\x1b[0m` reset followed by
`\x1b[${sgr}m` apply — not a combined `\x1b[0;${sgr}m` — to avoid
ambiguity with 256-color (`38;5;N`) and truecolor (`38;2;R;G;B`)
sub-parameter sequences that some terminal parsers handle differently
when preceded by a `0;` in the same CSI.

Source: tcell tracks `curstyle` and only emits SGR when `style != curstyle`.

### 8. Net scroll coalescing (macOS trackpad bounce fix)

**Impact:** Critical — eliminates scroll flicker on Magic Trackpad

macOS trackpads generate two types of scroll events that cause problems for
TUI applications:

1. **Momentum scrolling**: After lifting the finger, macOS continues
   generating scroll events with decreasing delta as inertia plays out.
2. **Rubber-band bounce**: When content hits a scroll boundary (top or
   bottom), macOS generates **reverse-direction** scroll events as part of
   the bounce-back physics. These arrive interleaved with the real scroll
   events: `↑↑↑↑↓↓↑↑↑↓↓`.

The terminal mouse protocol (`\x1b[<64;x;yM` / `\x1b[<65;x;yM`) strips
all phase and velocity information from these events. The TUI only sees
bare "scrollUp" / "scrollDown" with no way to distinguish user-initiated
from momentum/bounce events.

iTerm2's own developer (George Nachman) described macOS scroll wheels as
"a total shitshow" in `iTermScrollAccumulator.m`.

**The problem**: Without mitigation, each bounce event triggers a full
render cycle. The content visibly oscillates — e.g., the commit list jumps
back and forth by 3 lines per bounce event. This was especially severe on
the Magic Trackpad (external), which applies more aggressive momentum
curves than the built-in MacBook trackpad.

**Approaches tried and rejected:**

- **Time-based direction suppression** (suppress reverse scroll within
  150-300ms): Caught bounce events but also suppressed the user's
  intentional direction changes. The first 300ms of genuine scroll-up
  events after scrolling down were eaten, causing visible lag.

- **Ratio-based suppression** (suppress minority direction at 3:1 ratio):
  Similar problem — individual bounce events arrived before the ratio
  built up, so they got through.

- **Boundary no-op** (gocui pattern: skip state update when scroll would
  be a no-op at offset=0): Only prevents unnecessary re-renders when
  already AT the boundary. Doesn't help with bounce events that push
  content AWAY from the boundary before subsequent events push it back.

**The fix — net scroll coalescing:**

When scroll events arrive while Elm is processing (queued), instead of
coalescing only same-direction events, we **net ALL scroll events into a
single delta**. ScrollDown(+5) followed by ScrollUp(-3) becomes
ScrollDown(+2). The bounce cancels itself mathematically.

```js
// In the event queue handler:
const lastDelta = last.action === "scrollDown" ? last.amount : -last.amount;
const newDelta  = event.action === "scrollDown" ? event.amount : -event.amount;
const net = lastDelta + newDelta;
if (net > 0)      { last.action = "scrollDown"; last.amount = net; }
else if (net < 0) { last.action = "scrollUp";   last.amount = -net; }
else              { tuiEventQueue.pop(); } // net zero — remove entirely
```

This works because during the Elm round-trip (~1-5ms), multiple scroll
events accumulate in the queue. The bounce events arrive interleaved with
real events. Netting produces the correct cumulative scroll displacement,
and the single resulting event triggers one clean render.

**Why gocui/lazygit don't need this:**

gocui's `View.ScrollUp()` has an `if amount != 0` guard that makes
boundary scrolls a no-op. Combined with tcell's cell-level dirty
tracking, no-op scrolls write zero bytes to the terminal. But more
importantly, gocui/lazygit process events in-process (Go goroutines,
microsecond latency) rather than through IPC — so there's less time for
bounce events to accumulate between renders. Our BackendTask round-trip
is 1-5ms, giving macOS plenty of time to generate bounce events.

**Sources:**
- [iTerm2 `iTermScrollAccumulator.m`](https://github.com/gnachman/iTerm2):
  turnaround detection when delta × accumulated have opposite signs
- [WezTerm issue #2651](https://github.com/wez/wezterm/issues/2651):
  "scrolling down in Vim, once every couple of jumps down, the screen will
  jump up instead" — same macOS trackpad problem
- [Alacritty issue #2869](https://github.com/alacritty/alacritty/issues/2869):
  macOS applies different scroll acceleration to mouse wheels vs trackpads
- [Apple NSEvent documentation](https://developer.apple.com/documentation/appkit/nsevent):
  momentum phase lifecycle (MayBegin → Began → Changed → Ended)
- [gocui `view.go` ScrollUp/ScrollDown](https://github.com/jesseduffield/gocui):
  `if amount != 0` boundary guard pattern

### 9. Scroll boundary no-op (gocui pattern)

**Impact:** Medium — reduces unnecessary re-renders at scroll limits

When a scroll event would produce the same offset (already at top/bottom
boundary), the Layout returns the exact same State — no Dict.insert, no
field changes. This follows gocui's `if amount != 0` guard pattern.

Without this, every momentum scroll event at the boundary triggers a full
Elm update → view → encode → fill → diff cycle, even though zero cells
change. While the cell diff correctly finds nothing dirty and writes
nothing to the terminal, the CPU overhead of the encode+fill+diff for
1920+ cells per frame adds up during rapid trackpad momentum.

### 10. X10 mouse protocol fallback

**Impact:** Compatibility — enables mouse on Termux and older terminals

Added X10/normal mouse encoding parser (`\x1b[M` + 3 raw bytes) as fallback
for terminals that don't support SGR extended mode. Termux on Android uses
X10 encoding.

## Optimizations Tried and Reverted

### setImmediate event drain ❌

`setImmediate` defers resolution by one event loop tick even for single
events (the common case), adding ~1ms latency to every interaction. In Go,
non-blocking `select{}` has zero overhead when channels are empty. In
Node.js, there's no equivalent — `setImmediate` always defers.

### Scroll event coalescing with timer ❌

Batched rapid scroll events within an 8ms window and sent a single event
with `amount > 1`. The variable jump sizes (amount × 3 lines) felt choppy
compared to consistent 3-line scrolls. lazygit scrolls a fixed
`ScrollHeight` (default 3) per event — snappiness comes from processing
bursts quickly, not from bigger jumps.

**Lesson:** Consistent scroll distance > variable batched distance for
perceived smoothness.

**Note:** This was superseded by net scroll coalescing (section 8), which
uses queue-based coalescing during the Elm round-trip rather than a timer.
The key difference is that net coalescing handles opposite-direction events
(bounce cancellation), not just same-direction batching.

## Key Research Findings

### Rendering output size is NOT the bottleneck

For a scroll-down-one-row event in a 60-column view:
- tcell: ~219 bytes written to terminal
- Our approach: ~216 bytes

Nearly identical. The rendering technique is not where the gap was.

### Scroll "acceleration" is OS/terminal-level

lazygit does **zero** scroll acceleration. The feeling comes from:

1. **macOS trackpad**: faster swipe → larger pixel deltas AND higher frequency
2. **Terminal emulator** (iTerm2, Alacritty): accumulates pixel deltas, divides
   by line height, sends N separate `\x1b[<64;x;yM` sequences per accumulated
   line. iTerm2 applies exponential acceleration:
   `result = pow(fabs(delta), factor)`
3. **XTerm mouse protocol**: no delta field. Each sequence = exactly 1 tick.
4. **lazygit**: scrolls fixed `ScrollHeight` (default 3) lines per event.
   No velocity tracking, no acceleration code.

The acceleration is baked into event frequency by the time it reaches the app.
Our job is to process those bursts correctly (multi-sequence parsing) and
quickly (persistent queue + batch processing + render throttle).

### What makes lazygit feel smooth

1. Zero IPC latency — keypress to screen update is all in-process (~μs)
2. Event drain — multiple rapid events → one render
3. Synchronized output — atomic frame swaps
4. Only visible rows rendered
5. Cell-level dirty tracking — we now match this exactly

Our architecture matches 2-5. The IPC latency (#1) is inherent to the
BackendTask loop (~1-5ms per cycle). The TEA-based runtime would eliminate
this by keeping a persistent Elm event loop without port serialization.

### Terminal mouse reporting setup

Enable (on init):
```
\x1b[?1000h  — button event tracking (includes scroll wheel)
\x1b[?1006h  — SGR extended encoding (decimal coords, no size limit)
```

Disable (on cleanup):
```
\x1b[?1000l\x1b[?1006l
```

SGR format: `\x1b[<Cb;Cx;CyM` (press) / `\x1b[<Cb;Cx;Cym` (release)
- Cb bit 6 (0x40) = wheel event. low2: 0=up, 1=down
- Cb low2: 0=left, 1=middle, 2=right, 3=release (X10 only)
- Cx, Cy: 1-based coordinates (subtract 1 for 0-based)

X10 fallback: `\x1b[M` + 3 raw bytes (Cb+32, Cx+33, Cy+33)
