import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import vm from "node:vm";

describe("hmr connect", () => {
  it("closes the previous EventSource when connect is called again", () => {
    const hmrScript = readFileSync(
      new URL("../static-code/hmr.js", import.meta.url),
      "utf8"
    );

    const instances = [];

    class FakeEventSource {
      constructor(url) {
        this.url = url;
        this.closed = false;
        instances.push(this);
      }

      close() {
        this.closed = true;
      }
    }

    const sandbox = {
      console,
      EventSource: FakeEventSource,
      window: { location: { pathname: "/", origin: "http://localhost" } },
      setTimeout,
      clearTimeout,
      fetch: async () => {
        throw new Error("Unexpected fetch call in test.");
      },
    };

    vm.runInNewContext(hmrScript, sandbox);

    sandbox.connect(() => {}, false);
    sandbox.connect(() => {}, false);

    expect(instances).toHaveLength(2);
    expect(instances[0].closed).toBe(true);
    expect(instances[1].closed).toBe(false);
  });
});
