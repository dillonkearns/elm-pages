/**
 * Terminal input parser for TUI applications.
 *
 * Parses raw terminal input (escape sequences, mouse events, keypresses)
 * into structured event objects. Handles multi-sequence data chunks and
 * carries over partial escape sequences across calls.
 *
 * Extracted from render.js for testability.
 */

/**
 * Parse a single terminal event from the beginning of a string.
 * Returns { event, remaining } or null if unparseable.
 */
export function tuiParseSingleEvent(s) {
  // Bracketed paste: \x1b[200~ ... \x1b[201~
  // Content between markers is pasted text, delivered as a single event
  if (s.startsWith("\x1b[200~")) {
    const endMarker = "\x1b[201~";
    const endIdx = s.indexOf(endMarker, 6);
    if (endIdx >= 0) {
      const pastedText = s.slice(6, endIdx);
      const consumed = endIdx + endMarker.length;
      return {
        event: { type: "paste", text: pastedText },
        remaining: s.slice(consumed),
      };
    }
    // No end marker yet — treat entire remaining content as paste
    // (terminal should always send the end marker, but be defensive)
    return {
      event: { type: "paste", text: s.slice(6) },
      remaining: "",
    };
  }

  // SGR extended mouse: \x1b[<Cb;Cx;CyM or \x1b[<Cb;Cx;Cym
  const sgrMouseMatch = s.match(/^\x1b\[<(\d+);(\d+);(\d+)([Mm])/);
  if (sgrMouseMatch) {
    const consumed = sgrMouseMatch[0].length;
    const cb = parseInt(sgrMouseMatch[1], 10);
    const cx = parseInt(sgrMouseMatch[2], 10) - 1;
    const cy = parseInt(sgrMouseMatch[3], 10) - 1;
    const isRelease = sgrMouseMatch[4] === "m";
    const isWheel = (cb & 0x40) !== 0;
    const low2 = cb & 0x03;

    if (isWheel) {
      return {
        event: { type: "mouse", action: low2 === 0 ? "scrollUp" : "scrollDown", row: cy, col: cx },
        remaining: s.slice(consumed),
      };
    }
    if (isRelease) {
      return { event: null, remaining: s.slice(consumed) }; // skip releases
    }
    const buttons = ["left", "middle", "right"];
    return {
      event: { type: "mouse", action: "click", button: buttons[low2] || "left", row: cy, col: cx },
      remaining: s.slice(consumed),
    };
  }

  // X10/normal mouse: \x1b[M followed by 3 raw bytes (Cb Cx Cy)
  // Used by Termux and older terminals that don't support SGR mode
  if (s.length >= 6 && s.startsWith("\x1b[M")) {
    const cb = s.charCodeAt(3) - 32;
    const cx = s.charCodeAt(4) - 33; // 0-based
    const cy = s.charCodeAt(5) - 33;
    const isWheel = (cb & 0x40) !== 0;
    const low2 = cb & 0x03;

    if (isWheel) {
      return {
        event: { type: "mouse", action: low2 === 0 ? "scrollUp" : "scrollDown", row: cy, col: cx },
        remaining: s.slice(6),
      };
    }
    if (low2 === 3) {
      return { event: null, remaining: s.slice(6) }; // release in X10 mode
    }
    const buttons = ["left", "middle", "right"];
    return {
      event: { type: "mouse", action: "click", button: buttons[low2] || "left", row: cy, col: cx },
      remaining: s.slice(6),
    };
  }

  // Known escape sequences (fixed length)
  const escapeMap = {
    "\x1b[A": { type: "keypress", key: { tag: "Arrow", direction: "Up" }, modifiers: [] },
    "\x1b[B": { type: "keypress", key: { tag: "Arrow", direction: "Down" }, modifiers: [] },
    "\x1b[C": { type: "keypress", key: { tag: "Arrow", direction: "Right" }, modifiers: [] },
    "\x1b[D": { type: "keypress", key: { tag: "Arrow", direction: "Left" }, modifiers: [] },
    "\x1b[H": { type: "keypress", key: { tag: "Home" }, modifiers: [] },
    "\x1b[F": { type: "keypress", key: { tag: "End" }, modifiers: [] },
    "\x1b[5~": { type: "keypress", key: { tag: "PageUp" }, modifiers: [] },
    "\x1b[6~": { type: "keypress", key: { tag: "PageDown" }, modifiers: [] },
    "\x1b[3~": { type: "keypress", key: { tag: "Delete" }, modifiers: [] },
  };

  for (const [seq, event] of Object.entries(escapeMap)) {
    if (s.startsWith(seq)) {
      return { event, remaining: s.slice(seq.length) };
    }
  }

  // Escape key alone
  if (s.startsWith("\x1b") && s.length === 1) {
    return { event: { type: "keypress", key: { tag: "Escape" }, modifiers: [] }, remaining: "" };
  }

  // Unknown escape sequence — don't parse, let caller handle as leftover
  if (s.startsWith("\x1b")) {
    return null;
  }

  // Single-byte characters
  if (s.length >= 1) {
    const c = s.charCodeAt(0);

    if (c === 0x03) return { event: { _exit: true }, remaining: s.slice(1) };
    if (c === 0x0d || c === 0x0a) return { event: { type: "keypress", key: { tag: "Enter" }, modifiers: [] }, remaining: s.slice(1) };
    if (c === 0x09) return { event: { type: "keypress", key: { tag: "Tab" }, modifiers: [] }, remaining: s.slice(1) };
    if (c === 0x7f) return { event: { type: "keypress", key: { tag: "Backspace" }, modifiers: [] }, remaining: s.slice(1) };

    // Ctrl+letter
    if (c >= 1 && c <= 26) {
      const letter = String.fromCharCode(c + 96);
      return { event: { type: "keypress", key: { tag: "Character", char: letter }, modifiers: ["Ctrl"] }, remaining: s.slice(1) };
    }

    // Regular printable character
    if (c >= 32) {
      return { event: { type: "keypress", key: { tag: "Character", char: s.charAt(0) }, modifiers: [] }, remaining: s.slice(1) };
    }
  }

  return null; // unparseable
}

/**
 * Parse all events from a string, returning events and any leftover
 * partial sequence to carry over to the next data chunk.
 */
export function tuiParseAllEvents(s) {
  const events = [];
  let remaining = s;

  while (remaining.length > 0) {
    const result = tuiParseSingleEvent(remaining);
    if (result) {
      if (result.event) events.push(result.event);
      remaining = result.remaining;
    } else {
      // Unparseable. If it starts with ESC, it's likely a partial escape
      // sequence split across data chunks — carry it over for the next call.
      // If it doesn't start with ESC, discard one byte and continue parsing
      // (prevents garbage bytes from blocking the parser).
      if (remaining.length > 0 && remaining.charCodeAt(0) === 0x1b) {
        return { events, leftover: remaining };
      }
      // Discard unrecognizable non-escape byte and try the rest
      remaining = remaining.slice(1);
    }
  }
  return { events, leftover: "" };
}
