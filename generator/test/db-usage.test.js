import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { scriptUsesPagesDb } from "../src/db-usage.js";

let tmpDir;

beforeEach(async () => {
  tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "db-usage-test-"));
});

afterEach(async () => {
  await fs.promises.rm(tmpDir, { recursive: true });
});

function writeElmJson(projectDirectory, sourceDirectories) {
  fs.writeFileSync(
    path.join(projectDirectory, "elm.json"),
    JSON.stringify({
      type: "application",
      "source-directories": sourceDirectories,
      "elm-version": "0.19.1",
      dependencies: { direct: {}, indirect: {} },
      "test-dependencies": { direct: {}, indirect: {} },
    })
  );
}

describe("scriptUsesPagesDb", () => {
  it("returns true for direct Pages.Db import", async () => {
    writeElmJson(tmpDir, ["src"]);
    fs.mkdirSync(path.join(tmpDir, "src"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "src", "Main.elm"),
      `module Main exposing (run)

import Pages.Db

run = ()
`
    );

    const result = await scriptUsesPagesDb({
      projectDirectory: tmpDir,
      sourceDirectory: path.join(tmpDir, "src"),
      entryModuleName: "Main",
    });

    expect(result).toBe(true);
  });

  it("returns true for transitive Pages.Db import", async () => {
    writeElmJson(tmpDir, ["src"]);
    fs.mkdirSync(path.join(tmpDir, "src", "Local"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "src", "Main.elm"),
      `module Main exposing (run)

import Local.Helper

run = Local.Helper.value
`
    );
    fs.writeFileSync(
      path.join(tmpDir, "src", "Local", "Helper.elm"),
      `module Local.Helper exposing (value)

import Pages.Db

value = ()
`
    );

    const result = await scriptUsesPagesDb({
      projectDirectory: tmpDir,
      sourceDirectory: path.join(tmpDir, "src"),
      entryModuleName: "Main",
    });

    expect(result).toBe(true);
  });

  it("returns false when Pages.Db is not used", async () => {
    writeElmJson(tmpDir, ["src"]);
    fs.mkdirSync(path.join(tmpDir, "src", "Local"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "src", "Main.elm"),
      `module Main exposing (run)

import Local.Helper

run = Local.Helper.value
`
    );
    fs.writeFileSync(
      path.join(tmpDir, "src", "Local", "Helper.elm"),
      `module Local.Helper exposing (value)

import Html exposing (text)

value = text "ok"
`
    );

    const result = await scriptUsesPagesDb({
      projectDirectory: tmpDir,
      sourceDirectory: path.join(tmpDir, "src"),
      entryModuleName: "Main",
    });

    expect(result).toBe(false);
  });
});

