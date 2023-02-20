import * as assert from "assert";
import { describe, it } from "vitest";

import { toPathPattern, toPathPatterns } from "../src/route-codegen-helpers.js";

describe("toPathPattern", function () {
  it("index is normalized", function () {
    assert.strictEqual(toPathPattern(["Index"]), "/");
  });

  it("root-level optional param", function () {
    assert.deepStrictEqual(toPathPatterns(["Feed__"]), ["/", "/:feed"]);
  });
  it("dynamic segment", function () {
    assert.deepStrictEqual(toPathPatterns(["Blog", "Slug_"]), ["/blog/:slug"]);
  });
  it("index route", function () {
    assert.deepStrictEqual(toPathPatterns(["Index"]), ["/"]);
  });

  it("optional param", function () {
    assert.deepStrictEqual(toPathPatterns(["Docs", "Name__"]), [
      "/docs",
      "/docs/:name",
    ]);
  });
  // it("root-level splat", function () {
  //   assert.deepStrictEqual(toPathPatterns(["SPLAT_"]), ["/:root/*"]);
  // });
  // it("root-level optional splat", function () {
  //   assert.deepStrictEqual(toPathPatterns(["SPLAT__"]), ["/", "/:root/*"]);
  // });
});
