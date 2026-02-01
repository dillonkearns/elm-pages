import { dirname } from "node:path";
import { existsSync, unlinkSync } from "node:fs";
import * as process from "node:process";
import { fileURLToPath } from "node:url";
import { sync as spawnSync } from "cross-spawn";
import {
  afterAll,
  afterEach,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
} from "vitest";
import which from "which";
import { runElmCodegenInstall } from "../src/elm-codegen.js";

const originalWorkingDir = process.cwd();
const testDir = dirname(fileURLToPath(import.meta.url));
const originalPATH = process.env.PATH;
const [nodeFolder, elmFolder, elmCodegenFolder] = await Promise.all([
  which("node").then(dirname),
  which("elm").then(dirname),
  which("elm-codegen").then(dirname),
]);

// System paths needed for lamdera to spawn subprocesses
const systemPaths = ["/bin", "/usr/bin", "/usr/local/bin"].filter(
  (p) => existsSync(p)
);

function tryAndIgnore(thunk) {
  try {
    return thunk();
  } catch (_error) {}
}

function spawnLocalElmPages() {
  return new Promise((resolve) => {
    const { status, stderr, stdout } = spawnSync(
      "node_modules/.bin/elm-pages",
      ["run", "src/TestScript.elm"]
    );
    resolve({
      status,
      stderr: stderr.toString().trim(),
      stdout: stdout.toString().trim(),
    });
  });
}

// Since we muck with process.env.PATH in these tests,
// don't try to run them in parallel.
describe.sequential("runElmCodegenInstall", () => {
  beforeAll(() => {
    process.chdir(`${testDir}/missing-elm-codegen`);

    // Delete this file, if it exists, so we can make sure elm-codegen was
    // really run (because the file will get recreated).
    tryAndIgnore(() => unlinkSync("codegen/Gen/Basics.elm"));

    if (!existsSync("node_modules/")) {
      console.log("Running npm install in test project folder");
      spawnSync("npm", ["install"]);
    }
  });
  afterAll(() => {
    process.chdir(originalWorkingDir);
  });

  it("invokes elm-codegen", async () => {
    // Pre-condition: runElmCodegenInstall must be able to find `elm-codegen`.
    await expect(which("elm-codegen")).resolves.toEqual(expect.any(String));

    await expect(runElmCodegenInstall()).resolves.toEqual({ success: true });
    expect(existsSync("codegen/Gen/Basics.elm")).toBe(true);
  });

  describe("via elm-pages run", () => {
    beforeEach(() => {
      // Include system paths so lamdera can spawn subprocesses (sh, etc.)
      process.env.PATH = [nodeFolder, elmFolder, elmCodegenFolder, ...systemPaths].join(":");
    });
    afterEach(() => {
      process.env.PATH = originalPATH;
    });

    it("succeeds", async () => {
      expect(existsSync("node_modules/.bin/elm-pages")).toBe(true);

      await expect(spawnLocalElmPages()).resolves.toEqual(
        expect.objectContaining({
          status: 0,
          stderr: "",
          stdout: expect.stringMatching("Hello from TestScript"),
        })
      );

      expect(existsSync("codegen/Gen/Basics.elm")).toBe(true);
    });
  });

  describe("with elm-codegen missing", () => {
    beforeEach(() => {
      // Because the test runner is typically run via `npx` or `npm` from the
      // `generator` folder, our repository root's own `node_modules/.bin` will
      // be in PATH. JS package managers add `<root>/node_modules/.bin` to
      // PATH, where <root> is the current folder (if `package.json` exists) or
      // the closest parent folder where `package.json` exists. So to simulate
      // a project where elm-codegen is not installed, we have to hack PATH.
      process.env.PATH = [nodeFolder].join(":");
    });
    afterEach(() => {
      process.env.PATH = originalPATH;
    });

    it("returns a descriptive error", async () => {
      // Pre-condition: runElmCodegenInstall must fail to find `elm-codegen`.
      await expect(which("elm-codegen")).rejects.toThrow();

      await expect(runElmCodegenInstall()).resolves.toEqual(
        expect.objectContaining({
          success: false,
          message: expect.stringMatching("Unable to find elm-codegen"),
        })
      );
    });
  });
});
