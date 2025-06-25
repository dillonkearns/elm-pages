import { dirname } from "node:path";
import * as process from "node:process";
import { fileURLToPath } from "node:url";
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

describe.sequential("runElmCodegenInstall", () => {
  beforeAll(() => {
    process.chdir(`${testDir}/missing-elm-codegen`);
  });
  afterAll(() => {
    process.chdir(originalWorkingDir);
  });

  it("invokes elm-codegen", async () => {
    // Pre-condition: runElmCodegenInstall must be able to find `elm-codegen`.
    await expect(which("elm-codegen")).resolves.toEqual(expect.any(String));

    await expect(runElmCodegenInstall()).resolves.toEqual(undefined);
  });

  describe("when elm-codegen is missing", () => {
    beforeEach(() => {
      // Because the test runner is typically run via `npx` or `npm` from the
      // `generator` folder, our repository root's own `node_modules/.bin` will
      // be in PATH. JS package managers add `<root>/node_modules/.bin` to
      // PATH, where <root> is the current folder (if `package.json` exists) or
      // the closest parent folder where `package.json` exists. So to simulate
      // a project where elm-codegen is not installed, we have to hack PATH.
      process.env.PATH = "";
    });
    afterEach(() => {
      process.env.PATH = originalPATH;
    });

    it("throws a descriptive error", async () => {
      // Pre-condition: runElmCodegenInstall must fail to find `elm-codegen`.
      await expect(which("elm-codegen")).rejects.toThrow();

      await expect(runElmCodegenInstall()).rejects.toThrow(
        expect.objectContaining({
          name: "Error",
          message: expect.stringContaining("ENOENT"),
        })
      );
    });
  });
});
