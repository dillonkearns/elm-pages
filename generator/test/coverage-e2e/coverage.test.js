/**
 * End-to-end tests for `elm-pages run --coverage`.
 *
 * Runs a real elm-pages script with --coverage and asserts on the actual
 * user-visible output (console + lcov.info), approval-style.
 *
 * To update snapshots:
 *   npx vitest run generator/test/coverage-e2e/coverage.test.js --update
 */

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureDir = path.resolve(__dirname, "fixture");
const repoRoot = path.resolve(__dirname, "..", "..", "..");
const cliPath = path.resolve(__dirname, "..", "..", "src", "cli.js");

// Keep fixture elm.json pinned to the local package version and register it
// via elm-wrap so the Elm compiler can find it without a published release.
const elmPkgVersion = JSON.parse(
  fs.readFileSync(path.join(repoRoot, "elm.json"), "utf-8")
).version;

const fixtureElmJson = path.join(fixtureDir, "elm.json");
const fixtureElm = JSON.parse(fs.readFileSync(fixtureElmJson, "utf-8"));
fixtureElm.dependencies.direct["dillonkearns/elm-pages"] = elmPkgVersion;
fs.writeFileSync(fixtureElmJson, JSON.stringify(fixtureElm, null, 4) + "\n");

// Register local package so the Elm compiler can resolve it.
// Prefer elm-wrap if available; otherwise create a symlink directly.
const elmHome = process.env.ELM_HOME || path.join(process.env.HOME, ".elm");
const pkgPath = path.join(elmHome, "0.19.1", "packages", "dillonkearns", "elm-pages", elmPkgVersion);
const hasWrap = spawnSync("which", ["wrap"], { encoding: "utf-8" }).status === 0;
let createdSymlink = false;

if (hasWrap) {
  spawnSync("wrap", ["install", "--local-dev", "dillonkearns/elm-pages", "-y", "-q"], {
    cwd: repoRoot, encoding: "utf-8",
  });
} else if (!fs.existsSync(pkgPath)) {
  fs.mkdirSync(path.dirname(pkgPath), { recursive: true });
  fs.symlinkSync(repoRoot, pkgPath);
  createdSymlink = true;
}

afterAll(() => {
  if (hasWrap) {
    spawnSync("wrap", ["repository", "local-dev", "clear", "dillonkearns/elm-pages", elmPkgVersion], {
      encoding: "utf-8",
    });
  }
  if (createdSymlink) {
    try { fs.unlinkSync(pkgPath); } catch {}
  }
});


/** Replace machine-specific absolute paths with a placeholder. */
function normalize(text) {
  return text
    .replaceAll(fixtureDir, "<FIXTURE>")
    .replace(/\x1b\[[0-9;]*m/g, "")  // strip ANSI
    .replace(/data-\d+\.json/g, "data-PID.json");  // normalize PID in filenames
}

function runCoverage(extraArgs = []) {
  // Clean previous run (coverage artifacts are in elm-stuff/elm-pages/coverage/)
  for (const dir of ["coverage", "elm-stuff/elm-pages"]) {
    fs.rmSync(path.join(fixtureDir, dir), { recursive: true, force: true });
  }

  const result = spawnSync(
    "node",
    [cliPath, "run", "--coverage", ...extraArgs, "src/RunGreet.elm"],
    { cwd: fixtureDir, encoding: "utf-8", timeout: 120_000 }
  );

  const consoleOutput = normalize((result.stdout || "") + (result.stderr || ""));

  const lcovPath = path.join(fixtureDir, "coverage", "lcov.info");
  const lcovContent = fs.existsSync(lcovPath)
    ? normalize(fs.readFileSync(lcovPath, "utf-8"))
    : undefined;

  return { consoleOutput, lcovContent };
}

describe("elm-pages run --coverage", () => {
  let result;
  beforeAll(() => { result = runCoverage(); }, 120_000);

  it("console output matches snapshot", () => {
    expect(result.consoleOutput).toMatchSnapshot();
  });

  it("lcov.info matches snapshot", () => {
    expect(result.lcovContent).toBeDefined();
    expect(result.lcovContent).toMatchSnapshot();
  });
});

describe("elm-pages run --coverage --coverage-exclude", () => {
  let result;
  beforeAll(() => { result = runCoverage(["--coverage-exclude", "lib"]); }, 120_000);

  it("console output excludes Greet module", () => {
    expect(result.consoleOutput).toMatchSnapshot();
    // Greet is in lib/, which is excluded — should not appear as its own module
    expect(result.consoleOutput).not.toMatch(/^\s+Greet\s/m);
    // RunGreet is in src/, which is still included
    expect(result.consoleOutput).toContain("RunGreet");
  });

  it("lcov.info only contains non-excluded modules", () => {
    expect(result.lcovContent).toBeDefined();
    expect(result.lcovContent).toMatchSnapshot();
    expect(result.lcovContent).not.toContain("lib/Greet.elm");
    expect(result.lcovContent).toContain("RunGreet.elm");
  });
});

describe("elm-pages run --coverage --coverage-include", () => {
  let result;
  beforeAll(() => { result = runCoverage(["--coverage-include", "lib"]); }, 120_000);

  it("console output only includes Greet module", () => {
    expect(result.consoleOutput).toMatchSnapshot();
    expect(result.consoleOutput).toContain("Greet");
    expect(result.consoleOutput).not.toMatch(/\bRunGreet\b/);
  });

  it("lcov.info only contains included modules", () => {
    expect(result.lcovContent).toBeDefined();
    expect(result.lcovContent).toMatchSnapshot();
    expect(result.lcovContent).toContain("Greet.elm");
    expect(result.lcovContent).not.toContain("RunGreet.elm");
  });
});

describe("elm-pages run --coverage --coverage-exclude-module", () => {
  let result;
  beforeAll(() => { result = runCoverage(["--coverage-exclude-module", "RunGreet"]); }, 120_000);

  it("console output excludes the filtered module", () => {
    expect(result.consoleOutput).toMatchSnapshot();
    expect(result.consoleOutput).not.toMatch(/\bRunGreet\b/);
    expect(result.consoleOutput).toContain("Greet");
  });

  it("lcov.info excludes the filtered module", () => {
    expect(result.lcovContent).toBeDefined();
    expect(result.lcovContent).toMatchSnapshot();
    expect(result.lcovContent).toContain("Greet.elm");
    expect(result.lcovContent).not.toContain("RunGreet.elm");
  });
});

describe("error paths", () => {
  it("--coverage-include with no matches still runs the script", () => {
    const result = runCoverage(["--coverage-include", "nonexistent"]);
    // Script should still execute normally
    expect(result.consoleOutput).toContain("Hello, world!");
    // But warn that nothing was instrumented
    expect(result.consoleOutput).toContain("No user source directories");
    // No lcov.info should be produced
    expect(result.lcovContent).toBeUndefined();
  }, 120_000);

  it("stale lcov.info is cleaned before a coverage run", () => {
    // Write a stale lcov.info
    const lcovDir = path.join(fixtureDir, "coverage");
    fs.mkdirSync(lcovDir, { recursive: true });
    fs.writeFileSync(path.join(lcovDir, "lcov.info"), "STALE DATA");

    // Run with --coverage-include nonexistent so no new lcov is produced
    const result = runCoverage(["--coverage-include", "nonexistent"]);
    expect(result.consoleOutput).toContain("Hello, world!");

    // Stale lcov.info should have been cleaned
    expect(result.lcovContent).toBeUndefined();
  }, 120_000);
});
