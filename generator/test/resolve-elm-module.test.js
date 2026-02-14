import * as assert from "assert";
import { describe, it } from "vitest";
import { filePathToModuleName } from "../src/resolve-elm-module.js";

describe("filePathToModuleName", function () {
  it("converts single-level path", function () {
    assert.strictEqual(filePathToModuleName("Script.elm"), "Script");
  });

  it("converts two-level path", function () {
    assert.strictEqual(filePathToModuleName("Examples/Script.elm"), "Examples.Script");
  });

  it("converts deeply nested path", function () {
    assert.strictEqual(
      filePathToModuleName("Examples/Nested/Deep/Script.elm"),
      "Examples.Nested.Deep.Script"
    );
  });

  it("handles path without extension", function () {
    assert.strictEqual(filePathToModuleName("Foo/Bar/Baz"), "Foo.Bar.Baz");
  });
});
