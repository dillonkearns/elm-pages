// @ts-check

import * as fs from "node:fs";
import { tuiParseSingleEvent, tuiParseAllEvents } from "./tui-parser.js";

// ── Response helper ─────────────────────────────────────────────────────────

function jsonResponse(request, json) {
  return {
    request,
    response: { bodyKind: "json", body: json },
  };
}

// ── TUI State ───────────────────────────────────────────────────────────────

let tuiColorProfile = null; // detected once at init: 'truecolor' | '256' | '16' | 'mono'
let tuiActive = false;
// Scroll bounce suppression: macOS rubber-band effect sends reverse scroll
// events when hitting a boundary. The Magic Trackpad's aggressive momentum
// makes this especially visible. Track recent scroll direction + timestamp
// to suppress bounce-back events within a short window.
let tuiLastScrollDir = null; // 'scrollUp' | 'scrollDown' | null
let tuiLastScrollTime = 0;
/** @type {Map<number, ReturnType<typeof setInterval>>} */
let tuiTickTimers = new Map(); // intervalMs -> setInterval handle, one per subscribed interval
let tuiEventQueue = []; // events that arrived during Elm processing
let tuiEventResolve = null; // pending promise resolver for next wait
let tuiStdinLeftover = ""; // partial escape sequence carried across data chunks
let tuiDebugLog = null; // file descriptor for debug logging
let tuiLastRenderTime = 0; // timestamp of last actual terminal write
let tuiPendingRender = null; // deferred render to ensure final frame is shown
const TUI_MIN_RENDER_INTERVAL = 16; // ms — ~60fps cap, like Bubble Tea

// === Cell-level diffing state ===
// Replaces line-level tuiPrevLines approach. Each cell stores the character
// and its pre-computed SGR attribute string. Diffing per-cell instead of per-line
// means only changed characters emit escape sequences — the approach used by
// tcell (gocui/lazygit) and Ratatui's Buffer.
let tuiCellWidth = 0;
let tuiCellHeight = 0;
let tuiCurrCells = null; // current frame: flat array of {ch, sgr}
let tuiPrevCells = null; // previous frame: for diffing
let tuiLastScreenData = null; // raw screen data for resize bridge


// ── Cell Buffer Management ──────────────────────────────────────────────────

/** Allocate or resize cell buffers. Sentinel-fills prev to force full redraw. */
function tuiEnsureCellBuffers(w, h) {
  if (w <= 0 || h <= 0) return;
  if (w === tuiCellWidth && h === tuiCellHeight && tuiCurrCells) return;
  tuiCellWidth = w;
  tuiCellHeight = h;
  const size = w * h;
  tuiCurrCells = new Array(size);
  tuiPrevCells = new Array(size);
  for (let i = 0; i < size; i++) {
    tuiCurrCells[i] = { ch: ' ', sgr: '', link: '' };
    tuiPrevCells[i] = { ch: '\x00', sgr: '\x00', link: '\x00' }; // sentinel → forces full redraw
  }
}

/** Mark all prev cells as dirty so next flush redraws everything. */
function tuiInvalidatePrevCells() {
  if (!tuiPrevCells) return;
  for (let i = 0; i < tuiPrevCells.length; i++) {
    tuiPrevCells[i].ch = '\x00';
    tuiPrevCells[i].sgr = '\x00';
    tuiPrevCells[i].link = '\x00';
  }
}

/** Fill current cell buffer from Elm screen data (array of lines of styled spans). */
function tuiFillCells(screenData) {
  const w = tuiCellWidth;
  const h = tuiCellHeight;
  // Clear all cells to spaces with no style
  for (let i = 0; i < w * h; i++) {
    tuiCurrCells[i].ch = ' ';
    tuiCurrCells[i].sgr = '';
    tuiCurrCells[i].link = '';
  }
  if (!screenData) return;
  // Fill from screen data spans
  const lineCount = Math.min(screenData.length, h);
  for (let row = 0; row < lineCount; row++) {
    let col = 0;
    for (const span of screenData[row]) {
      const sgr = tuiStyleCodes(span.style);
      const link = span.style.hyperlink || '';
      // Iterate codepoints (handles multi-byte chars like box-drawing ╭─╮)
      for (const ch of span.text) {
        if (col >= w) break;
        const idx = row * w + col;
        tuiCurrCells[idx].ch = ch;
        tuiCurrCells[idx].sgr = sgr;
        tuiCurrCells[idx].link = link;
        col++;
      }
    }
  }
}

// ── Cell-Level Diff Renderer ────────────────────────────────────────────────

/**
 * Diff current cells against previous cells, write only changes to terminal.
 * Three key optimizations from tcell/ratatui:
 * 1. Skip unchanged cells entirely (the big win)
 * 2. Cache cursor position — skip movement for adjacent dirty cells
 * 3. Cache active SGR — skip style sequences for same-styled cells
 */
function tuiFlushCells(stdout) {
  tuiLastRenderTime = Date.now();
  const w = tuiCellWidth;
  const h = tuiCellHeight;
  if (!tuiCurrCells || !tuiPrevCells || w === 0 || h === 0) return;

  let buf = '\x1b[?2026h'; // begin synchronized update
  let dirty = false;
  let cRow = -1; // tracked cursor row (0-indexed)
  let cCol = -1; // tracked cursor col (0-indexed)
  let cSgr = null; // currently active SGR string on the terminal
  let cLink = null; // currently active OSC 8 hyperlink URL (null = none)

  for (let row = 0; row < h; row++) {
    for (let col = 0; col < w; col++) {
      const idx = row * w + col;
      const curr = tuiCurrCells[idx];
      const prev = tuiPrevCells[idx];

      // Skip unchanged cells
      if (curr.ch === prev.ch && curr.sgr === prev.sgr && curr.link === prev.link) continue;

      dirty = true;
      // Cursor movement: only emit when cursor isn't already here
      if (cRow !== row || cCol !== col) {
        if (cRow === row) {
          // Same row — use CUF (relative) or CHA (absolute column)
          const gap = col - cCol;
          if (gap === 1) {
            buf += '\x1b[C';
          } else if (gap > 1 && gap <= 4) {
            buf += `\x1b[${gap}C`;
          } else {
            buf += `\x1b[${col + 1}G`;
          }
        } else {
          // Different row — CUP (absolute positioning)
          buf += `\x1b[${row + 1};${col + 1}H`;
        }
      }

      // Style: only emit when SGR differs from current terminal state.
      // Use separate reset + apply (not combined \x1b[0;...m) to avoid
      // parser issues with 256-color/truecolor sub-parameter sequences.
      if (curr.sgr !== cSgr) {
        buf += '\x1b[0m';
        if (curr.sgr !== '') {
          buf += `\x1b[${curr.sgr}m`;
        }
        cSgr = curr.sgr;
      }

      // Hyperlink: emit OSC 8 sequences when link state changes.
      // Format: \x1b]8;;URL\x1b\\ to open, \x1b]8;;\x1b\\ to close.
      // Unsupported terminals silently ignore OSC 8.
      if (curr.link !== cLink) {
        if (cLink) {
          buf += '\x1b]8;;\x1b\\'; // close previous link
        }
        if (curr.link) {
          buf += `\x1b]8;;${curr.link}\x1b\\`; // open new link
        }
        cLink = curr.link;
      }

      buf += curr.ch;
      cCol = col + 1; // cursor auto-advances after write
      cRow = row;

      // Sync prev buffer so next frame diffs correctly
      prev.ch = curr.ch;
      prev.sgr = curr.sgr;
      prev.link = curr.link;
    }

    // Note: no \x1b[K here — unlike the old line-level approach, cell-level
    // diffing explicitly tracks every cell including trailing spaces, so EL
    // is not needed and would destructively erase unchanged cells to the right.
  }

  // Close any open hyperlink at end of frame
  if (cLink) {
    buf += '\x1b]8;;\x1b\\';
  }

  // Reset style at end of frame to leave terminal clean
  if (cSgr !== null && cSgr !== '') {
    buf += '\x1b[0m';
  }

  buf += '\x1b[?2026l'; // end synchronized update

  if (dirty) {
    stdout.write(buf);
  }
}

// ── Color Profile Detection & Conversion ────────────────────────────────────

/**
 * Detect terminal color profile from environment variables.
 * Follows charmbracelet/colorprofile's precedence order — the most
 * battle-tested approach across the Go TUI ecosystem.
 *
 * Returns: 'truecolor' | '256' | '16' | 'mono'
 */
function tuiDetectColorProfile() {
  const env = process.env;

  // NO_COLOR (https://no-color.org/): any non-empty value disables color.
  // Keeps bold/italic/underline — only strips color codes.
  if (env.NO_COLOR != null && env.NO_COLOR !== '') {
    return 'mono';
  }

  // COLORTERM: the most reliable truecolor indicator
  const colorterm = (env.COLORTERM || '').toLowerCase();
  if (colorterm === 'truecolor' || colorterm === '24bit') {
    return 'truecolor';
  }

  const term = (env.TERM || '').toLowerCase();

  // Known truecolor terminals (from charmbracelet/colorprofile)
  const truecolorTermPrefixes = [
    'alacritty', 'kitty', 'ghostty', 'wezterm',
    'foot', 'contour', 'rio', 'st-',
  ];
  if (truecolorTermPrefixes.some(t => term.startsWith(t)) || term === 'st') {
    return 'truecolor';
  }

  // Windows Terminal
  if (env.WT_SESSION) {
    return 'truecolor';
  }

  // TERM_PROGRAM: iTerm2, Hyper, mintty
  const termProgram = (env.TERM_PROGRAM || '').toLowerCase();
  if (['iterm.app', 'hyper', 'mintty'].includes(termProgram)) {
    return 'truecolor';
  }

  // TERM suffix checks
  if (term.endsWith('-direct')) return 'truecolor';
  if (term.includes('256color')) return '256';

  // CLICOLOR=0 means no color
  if (env.CLICOLOR === '0') return 'mono';

  // Safe default for any recognized terminal
  return '16';
}


/**
 * Convert RGB to nearest 256-color palette index.
 * Colors 16-231: 6x6x6 RGB cube. Colors 232-255: 24-step grayscale.
 * Same algorithm used by charmbracelet/colorprofile and Rich.
 */
function tuiRgbTo256(r, g, b) {
  // Check if it's close to grayscale
  if (Math.abs(r - g) <= 2 && Math.abs(g - b) <= 2) {
    if (r < 8) return 16;
    if (r > 248) return 231;
    return Math.round((r - 8) / 247 * 24) + 232;
  }
  // Map to 6x6x6 cube
  return 16
    + 36 * Math.round(r / 255 * 5)
    + 6 * Math.round(g / 255 * 5)
    + Math.round(b / 255 * 5);
}

/**
 * Convert a 256-color index to the nearest ANSI 16-color code.
 * Standard colors (0-7) map directly. Bright colors (8-15) map to bright.
 * Extended colors (16-255) use a simplified nearest-match.
 */
function tuiColor256To16(index, isBackground) {
  const offset = isBackground ? 10 : 0;
  // Standard 16 colors map directly
  if (index < 8) return 30 + index + offset;
  if (index < 16) return 82 + index + offset; // 90 + (index - 8) + offset

  // Extended colors: convert to RGB, then find nearest ANSI color
  let r, g, b;
  if (index >= 232) {
    // Grayscale ramp
    const v = (index - 232) * 10 + 8;
    r = v; g = v; b = v;
  } else {
    // 6x6x6 cube
    const ci = index - 16;
    r = Math.floor(ci / 36) * 51;
    g = Math.floor((ci % 36) / 6) * 51;
    b = (ci % 6) * 51;
  }
  return tuiRgbTo16(r, g, b, isBackground);
}

/**
 * Convert RGB to nearest ANSI 16-color SGR code.
 * Uses weighted distance in RGB space (redmean approximation, same as Rich).
 */
function tuiRgbTo16(r, g, b, isBackground) {
  const offset = isBackground ? 10 : 0;
  // The 16 ANSI colors in RGB (approximate, terminal-dependent)
  const ansi16 = [
    [0,0,0], [170,0,0], [0,170,0], [170,85,0],
    [0,0,170], [170,0,170], [0,170,170], [170,170,170],
    [85,85,85], [255,85,85], [85,255,85], [255,255,85],
    [85,85,255], [255,85,255], [85,255,255], [255,255,255],
  ];
  let bestIdx = 0;
  let bestDist = Infinity;
  for (let i = 0; i < 16; i++) {
    const [cr, cg, cb] = ansi16[i];
    // Redmean weighted distance (better perceptual match than Euclidean)
    const rmean = (r + cr) / 2;
    const dr = r - cr, dg = g - cg, db = b - cb;
    const dist = (2 + rmean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rmean) / 256) * db * db;
    if (dist < bestDist) {
      bestDist = dist;
      bestIdx = i;
    }
  }
  return String(bestIdx < 8 ? 30 + bestIdx + offset : 82 + bestIdx + offset);
}

// ── Terminal Control & Cleanup ──────────────────────────────────────────────

export function tuiCleanup() {
  if (!tuiActive) return;
  tuiActive = false;
  if (tuiDebugLog) {
    try {
      fs.writeSync(tuiDebugLog, `[${Date.now()}] tuiCleanup called\n`);
      fs.writeSync(tuiDebugLog, `  queue: ${tuiEventQueue.length}\n`);
      fs.closeSync(tuiDebugLog);
    } catch (e) {}
    tuiDebugLog = null;
  }
  const stdout = process.stdout;

  // Step 1: Disable mouse tracking and bracketed paste FIRST, while still
  // in raw mode. This tells the terminal to stop generating mouse events.
  // Must happen before setRawMode(false) — otherwise buffered mouse events
  // get echoed as visible escape sequences in the shell after exit.
  stdout.write(
    "\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l" + // disable all mouse modes
    "\x1b[?2004l"                                        // disable bracketed paste
  );

  // Step 2: Replace data listener with a no-op drain to consume and discard
  // any mouse/key events still in the stdin buffer or kernel pipe.
  process.stdin.removeAllListeners("data");
  process.stdin.on("data", () => {}); // consume and discard
  process.stdout.removeAllListeners("resize");

  // Step 3: Clear internal state
  tuiEventResolve = null;
  tuiEventQueue = [];
  tuiStdinLeftover = "";
  tuiCurrCells = null;
  tuiPrevCells = null;
  tuiLastScreenData = null;
  tuiCellWidth = 0;
  tuiCellHeight = 0;
  if (tuiPendingRender) {
    clearTimeout(tuiPendingRender);
    tuiPendingRender = null;
  }
  tuiTickTimers.forEach(clearInterval);
  tuiTickTimers.clear();

  // Step 4: Now safe to exit raw mode — mouse tracking is already off,
  // and the drain listener will consume any stragglers.
  process.stdin.removeAllListeners("data");
  if (process.stdin.isTTY && process.stdin.isRaw) {
    process.stdin.setRawMode(false);
  }
  process.stdin.pause();

  // Step 5: Complete terminal restoration
  stdout.write(
    "\x1b[0m" +                  // reset all text attributes
    "\x1b[?25h" +                // show cursor
    "\x1b[?1l\x1b>" +            // reset cursor keys to normal mode (DECRST + DECKPNM)
    "\x1b[?1049l"                // exit alternate screen (restores saved screen)
  );
}

// ── Input Parsing ───────────────────────────────────────────────────────────

/**
 * Parse terminal input, potentially containing multiple escape sequences.
 * Returns the first parseable event, and queues any additional events found
 * in the same data chunk (fixes dropped events from concatenated sequences).
 *
 * Maintains a leftover buffer across calls to handle data chunks that split
 * mid-escape-sequence. Without this, rapid scroll on macOS trackpads can
 * produce partial sequences like "64;119;45M" (missing the \x1b[< prefix)
 * that would be misinterpreted as keypresses.
 */
function tuiParseTerminalInput(data) {
  const s = tuiStdinLeftover + data.toString();
  tuiStdinLeftover = "";

  // Ctrl+C
  if (s === "\x03") {
    return { _exit: true };
  }

  // Try to parse multiple sequences from one data chunk.
  // Terminal emulators can concatenate escape sequences (especially during
  // fast scroll where iTerm2 sends N sequences from one OS event).
  const { events, leftover } = tuiParseAllEvents(s);
  tuiStdinLeftover = leftover;

  if (events.length === 0) {
    return null;
  }
  // Queue additional events beyond the first
  for (let i = 1; i < events.length; i++) {
    if (tuiEventResolve) {
      const resolve = tuiEventResolve;
      tuiEventResolve = null;
      resolve(events[i]);
    } else {
      tuiEventQueue.push(events[i]);
    }
  }
  return events[0];
}

// ── Style Utilities ─────────────────────────────────────────────────────────

/** Generate a cache key for a style object for quick comparison */
function tuiStyleKey(style) {
  if (!style) return "";
  let key = "";
  if (style.bold) key += "B";
  if (style.dim) key += "D";
  if (style.italic) key += "I";
  if (style.underline) key += "U";
  if (style.strikethrough) key += "S";
  if (style.inverse) key += "V";
  if (style.foreground) key += "f" + JSON.stringify(style.foreground);
  if (style.background) key += "b" + JSON.stringify(style.background);
  return key;
}

function tuiStyleCodes(style) {
  if (!style) return "";
  const codes = [];
  if (style.bold) codes.push("1");
  if (style.dim) codes.push("2");
  if (style.italic) codes.push("3");
  if (style.underline) codes.push("4");
  if (style.strikethrough) codes.push("9");
  if (style.inverse) codes.push("7");
  if (style.foreground) codes.push(tuiColorToAnsi(style.foreground, false));
  if (style.background) codes.push(tuiColorToAnsi(style.background, true));
  return codes.join(";");
}

/**
 * Convert a color value to an SGR code string, with automatic degradation
 * based on the detected terminal color profile.
 *
 * The Elm app writes colors in the highest fidelity it wants. The renderer
 * transparently downgrades based on tuiColorProfile — matching charmbracelet's
 * approach where the app always writes TrueColor and the framework handles it.
 *
 * Degradation path: TrueColor → 256-color → 16-color → mono (no color)
 */
function tuiColorToAnsi(color, isBackground) {
  const profile = tuiColorProfile || 'truecolor';

  // NO_COLOR / mono: strip all color codes (bold/italic preserved in tuiStyleCodes)
  if (profile === 'mono') return "";

  const offset = isBackground ? 10 : 0;

  if (typeof color === "string") {
    // Named ANSI colors (16-color) — always supported in any non-mono profile
    const colorMap = {
      black: 30, red: 31, green: 32, yellow: 33, blue: 34, magenta: 35, cyan: 36, white: 37,
      brightBlack: 90, brightRed: 91, brightGreen: 92, brightYellow: 93,
      brightBlue: 94, brightMagenta: 95, brightCyan: 96, brightWhite: 97,
    };
    const code = colorMap[color];
    if (code !== undefined) {
      return String(code >= 90 ? code + (isBackground ? 10 : 0) : code + offset);
    }
    return "";
  }

  if (color.r !== undefined) {
    // Truecolor (24-bit) — degrade based on profile
    if (profile === 'truecolor') {
      return `${isBackground ? 48 : 38};2;${color.r};${color.g};${color.b}`;
    }
    if (profile === '256') {
      return `${isBackground ? 48 : 38};5;${tuiRgbTo256(color.r, color.g, color.b)}`;
    }
    // 16-color: map to nearest ANSI color
    return tuiRgbTo16(color.r, color.g, color.b, isBackground);
  }

  if (color.color256 !== undefined) {
    // 256-color — degrade to 16-color if needed
    if (profile === 'truecolor' || profile === '256') {
      return `${isBackground ? 48 : 38};5;${color.color256}`;
    }
    // 16-color: map 256 to nearest ANSI color
    return tuiColor256To16(color.color256, isBackground);
  }

  return "";
}

// ── TUI Initialization ──────────────────────────────────────────────────────

export async function runTuiInit(req) {
  tuiActive = true;
  tuiLastScreenData = null; // reset for cell-level diffing
  const stdout = process.stdout;

  // Note: process signal handlers (SIGTERM, SIGINT, exit) are registered at
  // the top level of render.js so they cover both TUI and non-TUI scripts.
  // Those handlers call tuiCleanup() (exported from this module) to restore
  // the terminal when a TUI is active.

  // Single atomic write to avoid timing gaps where scroll events could leak.
  // Sequence: alternate screen, hide cursor, mouse tracking (button events +
  // SGR encoding), clear screen. tcell and Bubble Tea use the same modes.
  stdout.write(
    "\x1b[?1049h" + // enter alternate screen
    "\x1b[?25l" +   // hide cursor
    "\x1b[?1000h" + // enable button event mouse tracking (captures scroll)
    "\x1b[?1006h" + // enable SGR mouse encoding (decimal, no coord limit)
    "\x1b[?2004h" + // enable bracketed paste mode
    "\x1b[2J\x1b[H" // clear screen, cursor to top-left
  );

  // Set raw mode
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding("utf8");
  }

  // Persistent stdin listener — stays active during Elm processing so events
  // arriving between waits get queued instead of lost. This is gocui's pattern:
  // events queue up, and the next wait drains them all at once.
  tuiEventQueue = [];
  tuiEventResolve = null;
  tuiStdinLeftover = "";

  // Debug logging: set ELM_TUI_DEBUG=1 to write tui-debug.log for diagnosing input issues
  if (process.env.ELM_TUI_DEBUG) {
    try {
      tuiDebugLog = fs.openSync("tui-debug.log", "w");
      fs.writeSync(tuiDebugLog, `[${new Date().toISOString()}] TUI init\n`);
    } catch (e) { tuiDebugLog = null; }
  }

  process.stdin.on("data", (data) => {
    if (tuiDebugLog) {
      const raw = data.toString();
      const escaped = raw.replace(/\x1b/g, "\\x1b").replace(/[\x00-\x1f]/g, (c) => "\\x" + c.charCodeAt(0).toString(16).padStart(2, "0"));
      fs.writeSync(tuiDebugLog, `[${Date.now()}] stdin(${raw.length}): ${escaped}\n`);
      if (tuiStdinLeftover) {
        const loEsc = tuiStdinLeftover.replace(/\x1b/g, "\\x1b").replace(/[\x00-\x1f]/g, (c) => "\\x" + c.charCodeAt(0).toString(16).padStart(2, "0"));
        fs.writeSync(tuiDebugLog, `  leftover(${tuiStdinLeftover.length}): ${loEsc}\n`);
      }
    }

    const event = tuiParseTerminalInput(data);

    if (tuiDebugLog) {
      if (event) {
        fs.writeSync(tuiDebugLog, `  -> event: ${JSON.stringify(event)}\n`);
      } else {
        fs.writeSync(tuiDebugLog, `  -> null (no event)\n`);
      }
      if (tuiStdinLeftover) {
        const loEsc = tuiStdinLeftover.replace(/\x1b/g, "\\x1b").replace(/[\x00-\x1f]/g, (c) => "\\x" + c.charCodeAt(0).toString(16).padStart(2, "0"));
        fs.writeSync(tuiDebugLog, `  leftover after: ${loEsc}\n`);
      }
      fs.writeSync(tuiDebugLog, `  queue: ${tuiEventQueue.length}, resolve: ${!!tuiEventResolve}\n`);
    }

    if (!event) return;

    if (event._exit) {
      // tuiCleanup() and killActiveChildren() are called by the
      // process "exit" handler registered in render.js.
      process.exit(130);
      return;
    }

    // Track scroll for coalescing
    if (event.type === "mouse" && (event.action === "scrollUp" || event.action === "scrollDown")) {
      tuiLastScrollDir = event.action;
      tuiLastScrollTime = Date.now();
    }

    if (tuiEventResolve) {
      // A wait is pending — resolve immediately (zero latency)
      const resolve = tuiEventResolve;
      tuiEventResolve = null;
      resolve(event);
    } else {
      // No wait pending (Elm is processing) — queue for next wait.
      // Net scroll coalescing: merge ALL scroll events (both directions)
      // into a single net-delta event. This cancels out macOS rubber-band
      // bounce events mathematically: 5 scrollDowns + 3 scrollUps (bounce)
      // = net scrollDown with amount 2. One smooth scroll, no oscillation.
      const last = tuiEventQueue.length > 0 ? tuiEventQueue[tuiEventQueue.length - 1] : null;
      const isScroll = event.type === "mouse" && (event.action === "scrollUp" || event.action === "scrollDown");
      const lastIsScroll = last && last.type === "mouse" && (last.action === "scrollUp" || last.action === "scrollDown");
      if (isScroll && lastIsScroll) {
        // Net the deltas: down is positive, up is negative
        const lastDelta = last.action === "scrollDown" ? (last.amount || 1) : -(last.amount || 1);
        const newDelta = event.action === "scrollDown" ? (event.amount || 1) : -(event.amount || 1);
        const net = lastDelta + newDelta;
        if (net > 0) {
          last.action = "scrollDown";
          last.amount = net;
        } else if (net < 0) {
          last.action = "scrollUp";
          last.amount = -net;
        } else {
          // Net zero — remove the scroll event entirely
          tuiEventQueue.pop();
        }
      } else {
        tuiEventQueue.push(event);
      }
    }
  });

  // Listen for terminal resize.
  // 1. Immediately re-render last frame (instant visual feedback, no Elm round-trip)
  // 2. Queue a resize event for Elm to update Layout with new dimensions
  process.stdout.on("resize", () => {
    // Instant redraw: re-fill cell buffer from last screen data at new dimensions
    const newW = process.stdout.columns || 80;
    const newH = process.stdout.rows || 24;
    tuiEnsureCellBuffers(newW, newH);
    if (tuiLastScreenData && tuiLastScreenData.length > 0) {
      tuiFillCells(tuiLastScreenData);
      tuiInvalidatePrevCells();
      tuiFlushCells(process.stdout);
    }

    // Queue resize event for Elm (coalesce: replace any existing resize)
    const resizeEvent = {
      type: "resize",
      width: newW,
      height: newH,
    };

    if (tuiEventResolve) {
      const resolve = tuiEventResolve;
      tuiEventResolve = null;
      resolve(resizeEvent);
    } else {
      const existingIdx = tuiEventQueue.findIndex(e => e.type === "resize");
      if (existingIdx >= 0) {
        tuiEventQueue[existingIdx] = resizeEvent;
      } else {
        tuiEventQueue.push(resizeEvent);
      }
    }
  });

  // Initialize cell buffers for cell-level diffing
  tuiEnsureCellBuffers(stdout.columns || 80, stdout.rows || 24);

  // Detect color profile once at init (charmbracelet/colorprofile approach)
  tuiColorProfile = tuiDetectColorProfile();

  return jsonResponse(req, {
    width: stdout.columns || 80,
    height: stdout.rows || 24,
    colorProfile: tuiColorProfile,
  });
}

// ── Rendering ───────────────────────────────────────────────────────────────

export async function runTuiRender(req) {
  tuiRenderScreen(req.body.args[0]);
  return jsonResponse(req, null);
}

/**
 * Render screen data with cell-level diffing. Fills cell buffer from screen data,
 * then diffs each cell against the previous frame. Only changed cells emit escape
 * sequences — the tcell/ratatui approach ("cell-level delta rendering").
 */
function tuiRenderScreen(screenData) {
  const stdout = process.stdout;
  const w = stdout.columns || 80;
  const h = stdout.rows || 24;

  // Save for resize bridge
  tuiLastScreenData = screenData;

  // Ensure cell buffers match terminal dimensions
  tuiEnsureCellBuffers(w, h);

  // Fill current cell buffer from screen data
  tuiFillCells(screenData);

  // Frame rate throttle (like Bubble Tea's 60fps renderer cap).
  // Skip intermediate renders so slow displays aren't overwhelmed.
  // Schedule a deferred render so the final frame is always shown.
  const now = Date.now();
  if (now - tuiLastRenderTime < TUI_MIN_RENDER_INTERVAL) {
    // Too soon — schedule deferred render for when the interval elapses
    if (tuiPendingRender) clearTimeout(tuiPendingRender);
    tuiPendingRender = setTimeout(() => {
      tuiPendingRender = null;
      tuiFlushCells(stdout);
    }, TUI_MIN_RENDER_INTERVAL - (now - tuiLastRenderTime));
    return;
  }
  if (tuiPendingRender) {
    clearTimeout(tuiPendingRender);
    tuiPendingRender = null;
  }

  tuiFlushCells(stdout);
}

// ── Event Handling ──────────────────────────────────────────────────────────

export async function runTuiWaitEvent(req) {
  return runTuiWaitEventImpl(req);
}

async function runTuiWaitEventImpl(req) {
  const stdout = process.stdout;

  const makeResponse = (events) => {
    if (events.length === 1) {
      return jsonResponse(req, {
        event: events[0],
        width: stdout.columns || 80,
        height: stdout.rows || 24,
      });
    }
    return jsonResponse(req, {
      events: events,
      width: stdout.columns || 80,
      height: stdout.rows || 24,
    });
  };

  // If events queued up during Elm processing, return them all immediately.
  // This is the gocui drain pattern — zero latency, natural batching.
  if (tuiEventQueue.length > 0) {
    const events = tuiEventQueue;
    tuiEventQueue = [];
    return makeResponse(events);
  }

  // No queued events — wait for the next one
  return new Promise((resolve) => {
    tuiEventResolve = (event) => {
      resolve(makeResponse([event]));
    };
  });
}

export async function runTuiRenderAndWait(req) {
  // Combined render + wait in a single BackendTask round-trip
  const args = req.body.args[0];
  tuiRenderScreen(args.screen);

  // Diff subscribed tick intervals against active timers.
  // Each interval gets its own setInterval; ticks carry their interval + fire
  // timestamp so Elm-side routing can match subscriptions and pass Posix time.
  /** @type {number[]} */
  const wantIntervals = args.tickIntervals || [];

  // Clear timers we no longer need.
  tuiTickTimers.forEach((timer, interval) => {
    if (wantIntervals.indexOf(interval) === -1) {
      clearInterval(timer);
      tuiTickTimers.delete(interval);
    }
  });

  // Start timers for new intervals.
  wantIntervals.forEach((interval) => {
    if (!tuiTickTimers.has(interval)) {
      const timer = setInterval(() => {
        const tickEvent = { type: "tick", interval, time: Date.now() };
        if (tuiEventResolve) {
          const resolve = tuiEventResolve;
          tuiEventResolve = null;
          resolve(tickEvent);
        } else {
          // Per-interval coalescing: only one pending tick per interval.
          // On catch-up after a long block, the single pending tick carries
          // a fresh Date.now() so Elm sees the real elapsed time.
          const hasQueuedTick = tuiEventQueue.some(
            (e) => e.type === "tick" && e.interval === interval
          );
          if (!hasQueuedTick) {
            tuiEventQueue.push(tickEvent);
          }
        }
      }, interval);
      tuiTickTimers.set(interval, timer);
    }
  });

  return runTuiWaitEventImpl(req);
}

export async function runTuiExit(req) {
  tuiEventResolve = null;
  tuiEventQueue = [];
  process.stdin.removeAllListeners("data");
  tuiCleanup();
  return jsonResponse(req, null);
}
