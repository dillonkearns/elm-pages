/**
 * End-to-end tests for `elm-pages run --coverage`.
 *
 * Runs a real elm-pages script with --coverage and asserts on the generated
 * lcov.info output, approval-style. To update the approved snapshot:
 *
 *   npx vitest run generator/test/coverage-e2e/coverage.test.js --update
 *
 * Or delete the __snapshots__ directory and re-run.
 */

import { describe, it, expect, beforeAll } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureDir = path.join(__dirname, "fixture");
const cliPath = path.resolve(__dirname, "..", "..", "src", "cli.js");

/** Normalize absolute paths in lcov output so snapshots are portable. */
function normalizeLcov(lcov) {
  // Replace the fixture's absolute path with a placeholder
  return lcov.replaceAll(fixtureDir, "<FIXTURE>");
}

/** Normalize ANSI codes and absolute paths from console output. */
function normalizeConsole(output) {
  return output
    .replaceAll(fixtureDir, "<FIXTURE>")
    .replace(/\x1b\[[0-9;]*m/g, ""); // strip ANSI color codes
}

describe("elm-pages run --coverage", () => {
  let stdout;
  let lcovContent;

  beforeAll(() => {
    // Clean previous run
    for (const dir of [".coverage", "coverage", "elm-stuff/elm-pages"]) {
      fs.rmSync(path.join(fixtureDir, dir), { recursive: true, force: true });
    }

    // Run elm-pages with coverage
    const result = spawnSync("node", [cliPath, "run", "src/RunGreet.elm", "--coverage"], {
      cwd: fixtureDir,
      encoding: "utf-8",
      timeout: 120_000,
    });

    stdout = (result.stdout || "") + (result.stderr || "");

    if (!stdout.includes("Coverage Report")) {
      throw new Error(
        `elm-pages run --coverage failed (exit ${result.status}):\n${stdout}`
      );
    }

    lcovContent = fs.readFileSync(
      path.join(fixtureDir, "coverage", "lcov.info"),
      "utf-8"
    );
  }, 120_000);

  it("produces expected console output", () => {
    expect(normalizeConsole(stdout)).toMatchSnapshot();
  });

  it("produces expected lcov.info", () => {
    expect(normalizeLcov(lcovContent)).toMatchSnapshot();
  });

  it("writes lcov.info to coverage/lcov.info", () => {
    expect(fs.existsSync(path.join(fixtureDir, "coverage", "lcov.info"))).toBe(true);
  });

  it("instruments all user source modules", () => {
    expect(lcovContent).toContain("SF:");
    // Both Greet.elm and RunGreet.elm should appear
    expect(lcovContent).toContain("Greet.elm");
    expect(lcovContent).toContain("RunGreet.elm");
  });

  it("reports uncovered function formalGreet as FNDA:0", () => {
    expect(lcovContent).toContain("FNDA:0,formalGreet");
  });

  it("reports covered function greet with hits", () => {
    expect(lcovContent).toMatch(/FNDA:[1-9]\d*,greet/);
  });

  it("reports branch coverage for case expression", () => {
    // Hello and Goodbye branches should be hit
    expect(lcovContent).toMatch(/BRDA:\d+,0,0,[1-9]/); // first branch hit
    expect(lcovContent).toMatch(/BRDA:\d+,0,1,[1-9]/); // second branch hit
    // Custom branch should NOT be hit
    expect(lcovContent).toContain("BRDA:");
    const brdaLines = lcovContent.split("\n").filter((l) => l.startsWith("BRDA:"));
    const customBranch = brdaLines[2]; // third branch (Custom)
    expect(customBranch).toMatch(/BRDA:\d+,0,2,0/);
  });

  it("has correct LF/LH summary for Greet module", () => {
    // Extract the Greet section
    const sections = lcovContent.split("end_of_record");
    const greetSection = sections.find((s) => s.includes("Greet.elm") && !s.includes("RunGreet"));
    expect(greetSection).toBeDefined();

    // LH should be less than LF (formalGreet + Custom branch are uncovered)
    const lf = parseInt(greetSection.match(/LF:(\d+)/)[1]);
    const lh = parseInt(greetSection.match(/LH:(\d+)/)[1]);
    expect(lh).toBeLessThan(lf);
    expect(lh).toBeGreaterThan(0);
  });
});
