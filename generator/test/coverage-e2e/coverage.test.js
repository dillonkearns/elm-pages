/**
 * End-to-end tests for `elm-pages run --coverage`.
 *
 * Runs a real elm-pages script with --coverage and asserts on the actual
 * user-visible output (console + lcov.info), approval-style.
 *
 * To update snapshots:
 *   npx vitest run generator/test/coverage-e2e/coverage.test.js --update
 */

import { describe, it, expect, beforeAll } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureDir = path.resolve(__dirname, "fixture");
const cliPath = path.resolve(__dirname, "..", "..", "src", "cli.js");

/** Replace machine-specific absolute paths with a placeholder. */
function normalize(text) {
  return text
    .replaceAll(fixtureDir, "<FIXTURE>")
    .replace(/\x1b\[[0-9;]*m/g, "")  // strip ANSI
    .replace(/data-\d+\.json/g, "data-PID.json");  // normalize PID in filenames
}

describe("elm-pages run --coverage", () => {
  let consoleOutput;
  let lcovContent;

  beforeAll(() => {
    // Clean previous run
    for (const dir of [".coverage", "coverage", "elm-stuff/elm-pages"]) {
      fs.rmSync(path.join(fixtureDir, dir), { recursive: true, force: true });
    }

    const result = spawnSync("node", [cliPath, "run", "src/RunGreet.elm", "--coverage"], {
      cwd: fixtureDir,
      encoding: "utf-8",
      timeout: 120_000,
    });

    consoleOutput = normalize((result.stdout || "") + (result.stderr || ""));

    const lcovPath = path.join(fixtureDir, "coverage", "lcov.info");
    if (fs.existsSync(lcovPath)) {
      lcovContent = normalize(fs.readFileSync(lcovPath, "utf-8"));
    }
  }, 120_000);

  it("console output matches snapshot", () => {
    expect(consoleOutput).toMatchSnapshot();
  });

  it("lcov.info matches snapshot", () => {
    expect(lcovContent).toBeDefined();
    expect(lcovContent).toMatchSnapshot();
  });
});
