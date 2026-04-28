import { describe, it, expect } from "vitest";
import { __testing } from "../src/tui-runtime.js";

const plainStyle = {};

function span(text, style = plainStyle) {
  return { text, style };
}

describe("tui runtime renderer", () => {
  it("stores wide characters as two terminal cells", () => {
    const cells = __testing.fillCellsForTest(4, 1, [[span("表a")]]);

    expect(cells.map((cell) => cell.ch)).toEqual(["表", "", "a", " "]);
  });

  it("keeps combining marks in the same terminal cell as their base character", () => {
    const cells = __testing.fillCellsForTest(4, 1, [[span("e\u0301a")]]);

    expect(cells.map((cell) => cell.ch)).toEqual(["e\u0301", "a", " ", " "]);
  });

  it("does not write raw control sequences from text spans", () => {
    const output = __testing.renderToStringForTest(20, 1, [
      [span("safe\x1b[31mred")],
    ]);

    expect(output).not.toContain("\x1b[31mred");
    expect(output).toContain("safe[31mred");
  });

  it("does not write raw OSC terminators from hyperlink URLs", () => {
    const output = __testing.renderToStringForTest(20, 1, [
      [
        span("link", {
          hyperlink: "https://safe.example/\x1b]8;;file:///tmp\x1b\\",
        }),
      ],
    ]);

    expect(output).not.toContain(
      "https://safe.example/\x1b]8;;file:///tmp\x1b\\"
    );
    expect(output).toContain("https://safe.example/]8;;file:///tmp\\");
  });
});
