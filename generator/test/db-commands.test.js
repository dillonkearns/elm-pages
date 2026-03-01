import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as crypto from "node:crypto";

// We test the reset and init functions by calling them directly.
// They use process.cwd() for file resolution, so we chdir into a temp dir.
import { reset, init, migrate } from "../src/commands/db.js";
import { buildDbBin } from "../src/db-bin-format.js";
import { writeSchemaVersion } from "../src/db-schema.js";

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

describe("elm-pages db migrate", () => {
  const dbSource = `module Db exposing (Db, init)

type alias Db =
    { counter : Int
    }

init : Db
init =
    { counter = 0
    }
`;

  it("creates snapshot, stub, and MigrateChain.elm", async () => {
    // Set up Db.elm
    fs.mkdirSync(path.join(tmpDir, "script"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "script/elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.mkdirSync(path.join(tmpDir, "script/src"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "script/src/Db.elm"), dbSource);
    await writeSchemaVersion(tmpDir, 1);

    await migrate();

    // Snapshot V1.elm
    const snapshotPath = path.join(tmpDir, ".elm-pages-db", "Db", "V1.elm");
    expect(fs.existsSync(snapshotPath)).toBe(true);
    const snapshotContent = fs.readFileSync(snapshotPath, "utf8");
    expect(snapshotContent).toContain("module Db.V1 exposing");

    // Migration stub V2.elm
    const stubPath = path.join(
      tmpDir,
      ".elm-pages-db",
      "Db",
      "Migrate",
      "V2.elm"
    );
    expect(fs.existsSync(stubPath)).toBe(true);

    // MigrateChain.elm
    const chainPath = path.join(tmpDir, ".elm-pages-db", "MigrateChain.elm");
    expect(fs.existsSync(chainPath)).toBe(true);
    const chainContent = fs.readFileSync(chainPath, "utf8");
    expect(chainContent).toContain("module MigrateChain exposing (run)");

    // Schema version bumped to 2
    const versionPath = path.join(
      tmpDir,
      ".elm-pages-db",
      "schema-version.json"
    );
    const versionData = JSON.parse(fs.readFileSync(versionPath, "utf8"));
    expect(versionData.version).toBe(2);
  });

  it("prints guidance with pending migration and unimplemented stubs", async () => {
    const testHash = crypto.createHash("sha256").update("test").digest("hex");
    // Set up Db.elm
    fs.mkdirSync(path.join(tmpDir, "script"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "script/elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.mkdirSync(path.join(tmpDir, "script/src"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "script/src/Db.elm"), dbSource);

    // Create pending migration: db.bin at V1, schema at V2
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );
    await writeSchemaVersion(tmpDir, 2);

    const logSpy = vi.spyOn(console, "log");
    await migrate();

    const logOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(logOutput).toContain("Pending migration");
    logSpy.mockRestore();
  });
});
