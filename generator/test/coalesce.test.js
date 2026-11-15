import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { coalesce } from "../src/coalesce.js";

describe("coalesce", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("runs the function once for calls that come close together", () => {
    const run = vi.fn();
    const coalesced = coalesce(run, 30);

    coalesced();
    coalesced();
    coalesced();
    expect(run).not.toHaveBeenCalled();

    vi.advanceTimersByTime(30);
    expect(run).toHaveBeenCalledTimes(1);
  });

  it("waits until the calls stop coming", () => {
    const run = vi.fn();
    const coalesced = coalesce(run, 30);

    coalesced();
    vi.advanceTimersByTime(20);
    coalesced();
    vi.advanceTimersByTime(20);
    expect(run).not.toHaveBeenCalled();

    vi.advanceTimersByTime(10);
    expect(run).toHaveBeenCalledTimes(1);
  });

  it("runs the function again for a later call", () => {
    const run = vi.fn();
    const coalesced = coalesce(run, 30);

    coalesced();
    vi.advanceTimersByTime(30);
    coalesced();
    vi.advanceTimersByTime(30);

    expect(run).toHaveBeenCalledTimes(2);
  });

  it("does not wait forever when the calls never stop", () => {
    const run = vi.fn();
    const coalesced = coalesce(run, 30, { atMost: 100 });

    for (let elapsed = 0; elapsed < 200; elapsed += 10) {
      coalesced();
      vi.advanceTimersByTime(10);
    }

    expect(run.mock.calls.length).toBeGreaterThanOrEqual(1);
  });
});
