/**
 * The frozen view patch, applied to the real output of the installed `lamdera`
 * compiler (the other codemod tests use hand-written samples of compiled code).
 */

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { patchFrozenViews } from "../src/frozen-view-codemod.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureDir = path.join(__dirname, "fixtures/hot-reload");

/** @type {string} */
let projectDir;
/** @type {string} */
let patched;

/**
 * @param {string} code
 * @param {string} functionName
 * @returns {string} the source of a top-level function in compiled Elm code
 */
function functionSource(code, functionName) {
  const start = code.indexOf(`\nfunction ${functionName}(`);
  expect(start, `${functionName} should exist`).toBeGreaterThan(-1);
  return code.slice(start, code.indexOf("\n}\n", start));
}

beforeAll(() => {
  projectDir = fs.mkdtempSync(path.join(os.tmpdir(), "elm-pages-frozen-"));
  fs.cpSync(fixtureDir, projectDir, { recursive: true });
  const output = path.join(projectDir, "elm.js");
  const result = spawnSync(
    "lamdera",
    ["make", "src/NavApp.elm", `--output=${output}`],
    { cwd: projectDir, encoding: "utf8" }
  );
  if (result.status !== 0) {
    throw new Error(`lamdera make failed:\n${result.stdout}\n${result.stderr}`);
  }
  patched = patchFrozenViews(fs.readFileSync(output, "utf8"));
}, 120000);

afterAll(() => {
  fs.rmSync(projectDir, { recursive: true, force: true });
});

describe("frozen view patch on real lamdera output", () => {
  it("draws a frozen view from its saved HTML when rendering from scratch", () => {
    // The app's first render replaces the server-rendered page, so frozen
    // views are drawn by `_VirtualDom_render`, not found by the diff.
    const render = functionSource(patched, "_VirtualDom_render");

    expect(render).toContain("__ELM_PAGES_FROZEN_VIEWS__");
    expect(render).toContain("__ELM_PAGES_STATIC__");
  });

  it("keeps or swaps a frozen view when diffing", () => {
    const diff = functionSource(patched, "_VirtualDom_diffHelp");

    expect(diff).toContain("data-static");
    expect(diff).toContain("__ELM_PAGES_STATIC__");
  });

  it("is still valid JavaScript", () => {
    expect(() => new Function(patched)).not.toThrow();
  });
});
