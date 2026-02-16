import { describe, expect, it } from "vitest";
import { toExactBuffer } from "../src/binary-helpers.js";

describe("toExactBuffer", () => {
  it("preserves only the bytes in a Uint8Array view", () => {
    const base = new Uint8Array([10, 20, 30, 40, 50, 60]);
    const view = base.subarray(2, 5);

    const result = toExactBuffer(view);

    expect([...result]).toEqual([30, 40, 50]);
  });

  it("preserves only the bytes in a DataView", () => {
    const base = new Uint8Array([1, 2, 3, 4, 5, 6, 7]);
    const view = new DataView(base.buffer, 1, 4);

    const result = toExactBuffer(view);

    expect([...result]).toEqual([2, 3, 4, 5]);
  });
});
