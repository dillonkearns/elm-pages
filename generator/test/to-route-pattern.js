var assert = require("assert");
const { toPathPattern } = require("../src/route-codegen-helpers.js");

describe("toPathPattern", function () {
  it("index is normalized", function () {
    assert.strictEqual(toPathPattern(["Index"]), "/");
  });
});
