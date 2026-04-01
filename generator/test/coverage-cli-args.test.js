/**
 * Tests for position-aware coverage flag extraction.
 *
 * Coverage flags before the script path go to elm-pages.
 * Coverage flags after the script path are ignored (forwarded to the script).
 */

import { describe, it, expect } from "vitest";
import { extractCoverageFlags } from "../src/coverage-cli.js";

// Simulate process.argv: ["node", "elm-pages", "run", ...args]
const argv = (...args) => ["node", "elm-pages", "run", ...args];

describe("extractCoverageFlags", () => {
  it("--coverage before script path enables coverage", () => {
    const result = extractCoverageFlags("src/Script.elm", argv("--coverage", "src/Script.elm"));
    expect(result.coverage).toBe(true);
  });

  it("--coverage after script path does NOT enable coverage", () => {
    const result = extractCoverageFlags("src/Script.elm", argv("src/Script.elm", "--coverage"));
    expect(result.coverage).toBe(false);
  });

  it("--coverage-include before script path is captured", () => {
    const result = extractCoverageFlags("src/Script.elm",
      argv("--coverage", "--coverage-include", "lib", "src/Script.elm"));
    expect(result.coverage).toBe(true);
    expect(result.coverageInclude).toEqual(["lib"]);
  });

  it("--coverage-include after script path is NOT captured", () => {
    const result = extractCoverageFlags("src/Script.elm",
      argv("--coverage", "src/Script.elm", "--coverage-include", "lib"));
    expect(result.coverage).toBe(true);
    expect(result.coverageInclude).toEqual([]);
  });

  it("multiple --coverage-include before script path", () => {
    const result = extractCoverageFlags("src/Script.elm",
      argv("--coverage-include", "src", "--coverage-include", "lib", "src/Script.elm"));
    expect(result.coverageInclude).toEqual(["src", "lib"]);
  });

  it("--coverage-exclude before script path", () => {
    const result = extractCoverageFlags("src/Script.elm",
      argv("--coverage-exclude", "vendor", "src/Script.elm"));
    expect(result.coverageExclude).toEqual(["vendor"]);
  });

  it("--coverage-include-module before script path", () => {
    const result = extractCoverageFlags("src/Script.elm",
      argv("--coverage-include-module", "MyApp.*", "src/Script.elm"));
    expect(result.coverageIncludeModule).toEqual(["MyApp.*"]);
  });

  it("--coverage-exclude-module before script path", () => {
    const result = extractCoverageFlags("src/Script.elm",
      argv("--coverage-exclude-module", "Gen.*", "src/Script.elm"));
    expect(result.coverageExcludeModule).toEqual(["Gen.*"]);
  });

  it("no coverage flags", () => {
    const result = extractCoverageFlags("src/Script.elm",
      argv("src/Script.elm", "--seed", "42"));
    expect(result.coverage).toBe(false);
    expect(result.coverageInclude).toEqual([]);
  });

  it("script path not found returns empty defaults", () => {
    const result = extractCoverageFlags("missing.elm",
      argv("--coverage", "src/Script.elm"));
    expect(result.coverage).toBe(false);
  });
});
