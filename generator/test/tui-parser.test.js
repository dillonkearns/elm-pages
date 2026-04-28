import { describe, it, expect } from "vitest";
import { tuiParseSingleEvent, tuiParseAllEvents } from "../src/tui-parser.js";

describe("tuiParseSingleEvent", () => {
  describe("SGR mouse events", () => {
    it("parses scroll down", () => {
      const result = tuiParseSingleEvent("\x1b[<65;10;20M");
      expect(result.event).toEqual({ type: "mouse", action: "scrollDown", row: 19, col: 9 });
      expect(result.remaining).toBe("");
    });

    it("parses scroll up", () => {
      const result = tuiParseSingleEvent("\x1b[<64;5;3M");
      expect(result.event).toEqual({ type: "mouse", action: "scrollUp", row: 2, col: 4 });
      expect(result.remaining).toBe("");
    });

    it("parses left click", () => {
      const result = tuiParseSingleEvent("\x1b[<0;15;8M");
      expect(result.event).toEqual({ type: "mouse", action: "click", button: "left", row: 7, col: 14 });
      expect(result.remaining).toBe("");
    });

    it("skips mouse release events", () => {
      const result = tuiParseSingleEvent("\x1b[<0;15;8m");
      expect(result.event).toBeNull();
      expect(result.remaining).toBe("");
    });

    it("preserves remaining text after mouse event", () => {
      const result = tuiParseSingleEvent("\x1b[<65;10;20Mhello");
      expect(result.event.action).toBe("scrollDown");
      expect(result.remaining).toBe("hello");
    });
  });

  describe("key events", () => {
    it("parses arrow keys", () => {
      expect(tuiParseSingleEvent("\x1b[A").event.key.direction).toBe("Up");
      expect(tuiParseSingleEvent("\x1b[B").event.key.direction).toBe("Down");
      expect(tuiParseSingleEvent("\x1b[C").event.key.direction).toBe("Right");
      expect(tuiParseSingleEvent("\x1b[D").event.key.direction).toBe("Left");
    });

    it("parses printable characters", () => {
      const result = tuiParseSingleEvent("q");
      expect(result.event).toEqual({ type: "keypress", key: { tag: "Character", char: "q" }, modifiers: [] });
      expect(result.remaining).toBe("");
    });

    it("parses enter", () => {
      expect(tuiParseSingleEvent("\r").event.key.tag).toBe("Enter");
    });

    it("parses escape alone", () => {
      expect(tuiParseSingleEvent("\x1b").event.key.tag).toBe("Escape");
    });

    it("parses Ctrl+C as exit", () => {
      expect(tuiParseSingleEvent("\x03").event._exit).toBe(true);
    });

    it("parses Ctrl+letter", () => {
      const result = tuiParseSingleEvent("\x01"); // Ctrl+A
      expect(result.event.key.char).toBe("a");
      expect(result.event.modifiers).toEqual(["Ctrl"]);
    });

    it("parses Shift+Tab (Back Tab)", () => {
      const result = tuiParseSingleEvent("\x1b[Z");
      expect(result.event).toEqual({
        type: "keypress",
        key: { tag: "Tab" },
        modifiers: ["Shift"],
      });
      expect(result.remaining).toBe("");
    });

    it("parses Shift+Tab with remaining input", () => {
      const result = tuiParseSingleEvent("\x1b[Zq");
      expect(result.event.key.tag).toBe("Tab");
      expect(result.event.modifiers).toEqual(["Shift"]);
      expect(result.remaining).toBe("q");
    });
  });

  describe("bracketed paste", () => {
    it("parses paste with end marker", () => {
      const result = tuiParseSingleEvent("\x1b[200~hello world\x1b[201~");
      expect(result.event).toEqual({ type: "paste", text: "hello world" });
      expect(result.remaining).toBe("");
    });

    it("preserves remaining after paste", () => {
      const result = tuiParseSingleEvent("\x1b[200~pasted\x1b[201~q");
      expect(result.event.text).toBe("pasted");
      expect(result.remaining).toBe("q");
    });
  });

  describe("partial/unknown escape sequences", () => {
    it("returns null for partial SGR mouse (split mid-sequence)", () => {
      // This is the key fix: "\x1b[<65;10" is a partial mouse event
      // that got split across data chunks. Should NOT fall through
      // to character parsing.
      const result = tuiParseSingleEvent("\x1b[<65;10");
      expect(result).toBeNull();
    });

    it("returns null for bare ESC followed by unknown sequence", () => {
      const result = tuiParseSingleEvent("\x1b[999z");
      expect(result).toBeNull();
    });

    it("returns null for lone ESC with more text (not standalone)", () => {
      // ESC + "[" but not a known sequence
      const result = tuiParseSingleEvent("\x1b[");
      expect(result).toBeNull();
    });
  });
});

describe("tuiParseAllEvents", () => {
  describe("multiple events in one chunk", () => {
    it("parses concatenated scroll events", () => {
      const input = "\x1b[<65;10;20M\x1b[<65;10;20M\x1b[<65;10;20M";
      const { events, leftover } = tuiParseAllEvents(input);
      expect(events).toHaveLength(3);
      expect(events[0].action).toBe("scrollDown");
      expect(events[1].action).toBe("scrollDown");
      expect(events[2].action).toBe("scrollDown");
      expect(leftover).toBe("");
    });

    it("parses mixed event types in one chunk", () => {
      const input = "\x1b[<65;10;20Mq\x1b[A";
      const { events, leftover } = tuiParseAllEvents(input);
      expect(events).toHaveLength(3);
      expect(events[0].action).toBe("scrollDown");
      expect(events[1].key.char).toBe("q");
      expect(events[2].key.direction).toBe("Up");
      expect(leftover).toBe("");
    });

    it("skips mouse releases in batch", () => {
      // Press + release: press is kept, release is filtered
      const input = "\x1b[<0;5;3M\x1b[<0;5;3m";
      const { events, leftover } = tuiParseAllEvents(input);
      expect(events).toHaveLength(1);
      expect(events[0].action).toBe("click");
      expect(leftover).toBe("");
    });
  });

  describe("partial sequence carryover", () => {
    it("carries over partial SGR mouse at end of chunk", () => {
      // First chunk ends mid-mouse-sequence
      const input = "\x1b[<65;10;20M\x1b[<65;15";
      const { events, leftover } = tuiParseAllEvents(input);
      expect(events).toHaveLength(1);
      expect(events[0].action).toBe("scrollDown");
      expect(leftover).toBe("\x1b[<65;15");
    });

    it("partial carryover completes in next call", () => {
      // Simulate two data chunks splitting a mouse event
      const chunk1 = "\x1b[<65;154";
      const chunk2 = ";62M";

      // First chunk: nothing parseable, leftover saved
      const result1 = tuiParseAllEvents(chunk1);
      expect(result1.events).toHaveLength(0);
      expect(result1.leftover).toBe("\x1b[<65;154");

      // Second chunk: prepend leftover, now complete
      const result2 = tuiParseAllEvents(result1.leftover + chunk2);
      expect(result2.events).toHaveLength(1);
      expect(result2.events[0].action).toBe("scrollDown");
      expect(result2.leftover).toBe("");
    });

    it("carries over partial arrow key sequence", () => {
      const input = "q\x1b[";
      const { events, leftover } = tuiParseAllEvents(input);
      expect(events).toHaveLength(1);
      expect(events[0].key.char).toBe("q");
      expect(leftover).toBe("\x1b[");
    });

    it("partial arrow completes in next chunk", () => {
      const chunk1 = "\x1b[";
      const chunk2 = "A";

      const result1 = tuiParseAllEvents(chunk1);
      expect(result1.events).toHaveLength(0);
      expect(result1.leftover).toBe("\x1b[");

      const result2 = tuiParseAllEvents(result1.leftover + chunk2);
      expect(result2.events).toHaveLength(1);
      expect(result2.events[0].key.direction).toBe("Up");
    });
  });

  describe("leftover cap", () => {
    it("discards overly long unknown escape sequences instead of accumulating", () => {
      // An unknown ESC sequence longer than 32 bytes should not stay in leftover
      const longUnknown = "\x1b[" + "x".repeat(40) + "q";
      const { events, leftover } = tuiParseAllEvents(longUnknown);
      // Should recover and parse 'q' after discarding the unknown sequence
      expect(events.some(e => e.key && e.key.char === "q")).toBe(true);
      expect(leftover).toBe("");
    });
  });

  describe("garbage/noise handling", () => {
    it("discards non-printable non-escape garbage bytes", () => {
      // Low bytes (0x00, 0x1C-0x1F) that aren't Ctrl+letter or known keys
      // should be skipped, not crash the parser
      const input = "\x1cq";
      const { events, leftover } = tuiParseAllEvents(input);
      // \x1c is not a known key, gets skipped; 'q' is parsed
      expect(events).toHaveLength(1);
      expect(events[0].key.char).toBe("q");
      expect(leftover).toBe("");
    });

    it("does not interpret SGR digits as keypresses", () => {
      // This is the crash scenario: "64;119;45M" from a split sequence
      // WITHOUT the \x1b[< prefix. Should not produce 6, 4, ;, etc. as keys.
      // These are regular printable chars, but the point is they should
      // NOT be interpreted when they come from a split escape sequence.
      // With the fix, the partial \x1b[< would have been carried over,
      // so this naked data should never reach the parser alone.
      // But if it does, it's handled gracefully (individual chars, no crash).
      const input = "64;119;45M";
      const { events } = tuiParseAllEvents(input);
      // These are printable characters, so they get parsed as character events
      // The key insight is: with carryover, this should never happen
      expect(events.length).toBeGreaterThan(0);
      // Verify no crash and no exit event
      expect(events.every(e => !e._exit)).toBe(true);
    });

    it("does not crash on empty input", () => {
      const { events, leftover } = tuiParseAllEvents("");
      expect(events).toHaveLength(0);
      expect(leftover).toBe("");
    });
  });

  describe("rapid scroll simulation (macOS trackpad)", () => {
    it("handles a burst of many scroll events in one chunk", () => {
      // Simulate macOS trackpad momentum: 20 scroll events in one data callback
      const scrollEvent = "\x1b[<65;154;62M";
      const input = scrollEvent.repeat(20);
      const { events, leftover } = tuiParseAllEvents(input);
      expect(events).toHaveLength(20);
      expect(events.every(e => e.action === "scrollDown")).toBe(true);
      expect(leftover).toBe("");
    });

    it("handles burst ending with partial sequence", () => {
      // 5 complete scroll events + partial 6th
      const scrollEvent = "\x1b[<65;154;62M";
      const input = scrollEvent.repeat(5) + "\x1b[<65;154";
      const { events, leftover } = tuiParseAllEvents(input);
      expect(events).toHaveLength(5);
      expect(leftover).toBe("\x1b[<65;154");
    });

    it("handles scroll burst with keypress in the middle", () => {
      const scroll = "\x1b[<65;10;20M";
      const input = scroll + scroll + "q" + scroll;
      const { events, leftover } = tuiParseAllEvents(input);
      expect(events).toHaveLength(4);
      expect(events[0].action).toBe("scrollDown");
      expect(events[1].action).toBe("scrollDown");
      expect(events[2].key.char).toBe("q");
      expect(events[3].action).toBe("scrollDown");
      expect(leftover).toBe("");
    });
  });
});
