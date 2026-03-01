import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

// We test the reset and init functions by calling them directly.
// They use process.cwd() for file resolution, so we chdir into a temp dir.
import { reset, init } from "../src/commands/db.js";

let tmpDir;
let originalCwd;

beforeEach(async () => {
  tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "db-cmd-test-"));
  originalCwd = process.cwd();
  process.chdir(tmpDir);
});

afterEach(async () => {
  process.chdir(originalCwd);
  await fs.promises.rm(tmpDir, { recursive: true });
});

describe("elm-pages db reset", () => {
  it("does nothing when no db.bin exists", async () => {
    await reset({ force: true });
    // Should not throw
  });

  it("deletes db.bin when it exists", async () => {
    fs.writeFileSync(path.join(tmpDir, "db.bin"), "test data");
    expect(fs.existsSync(path.join(tmpDir, "db.bin"))).toBe(true);

    await reset({ force: true });

    expect(fs.existsSync(path.join(tmpDir, "db.bin"))).toBe(false);
  });

  it("deletes db.lock when it exists", async () => {
    fs.writeFileSync(path.join(tmpDir, "db.lock"), '{"pid":1}');
    expect(fs.existsSync(path.join(tmpDir, "db.lock"))).toBe(true);

    await reset({ force: true });

    expect(fs.existsSync(path.join(tmpDir, "db.lock"))).toBe(false);
  });

  it("deletes both db.bin and db.lock together", async () => {
    fs.writeFileSync(path.join(tmpDir, "db.bin"), "data");
    fs.writeFileSync(path.join(tmpDir, "db.lock"), "lock");

    await reset({ force: true });

    expect(fs.existsSync(path.join(tmpDir, "db.bin"))).toBe(false);
    expect(fs.existsSync(path.join(tmpDir, "db.lock"))).toBe(false);
  });
});

describe("elm-pages db init", () => {
  it("creates Db.elm in first source-directory from script/elm.json", async () => {
    // Set up a script/elm.json pointing to script/src
    fs.mkdirSync(path.join(tmpDir, "script"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "script/elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );

    await init();

    const dbElmPath = path.join(tmpDir, "script/src/Db.elm");
    expect(fs.existsSync(dbElmPath)).toBe(true);

    const content = fs.readFileSync(dbElmPath, "utf8");
    expect(content).toContain("module Db exposing");
    expect(content).toContain("type alias Db");
    expect(content).toContain("init : Db");
  });

  it("creates Db.elm in first source-directory from elm.json", async () => {
    fs.writeFileSync(
      path.join(tmpDir, "elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );

    await init();

    const dbElmPath = path.join(tmpDir, "src/Db.elm");
    expect(fs.existsSync(dbElmPath)).toBe(true);
  });

  it("does not overwrite existing Db.elm", async () => {
    fs.writeFileSync(
      path.join(tmpDir, "elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.mkdirSync(path.join(tmpDir, "src"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "src/Db.elm"), "-- my custom Db");

    await init();

    const content = fs.readFileSync(path.join(tmpDir, "src/Db.elm"), "utf8");
    expect(content).toBe("-- my custom Db");
  });
});
