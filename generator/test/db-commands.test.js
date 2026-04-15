import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as crypto from "node:crypto";

// We test db command functions by calling them directly.
// They use process.cwd() for file resolution, so we chdir into a temp dir.
import { init, migrate, status } from "../src/commands/db.js";
import { buildDbBin } from "../src/db-bin-format.js";
import { computeSchemaHash, readSchemaVersion } from "../src/db-schema.js";

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
  process.exitCode = undefined;
});

function setupSchemaVersion(dir, version) {
  const migrateDir = path.join(dir, "db", "Db", "Migrate");
  fs.mkdirSync(migrateDir, { recursive: true });
  for (let v = 1; v <= version; v++) {
    const p = path.join(migrateDir, `V${v}.elm`);
    if (!fs.existsSync(p))
      fs.writeFileSync(p, `module Db.Migrate.V${v} exposing (..)\nstub = ()\n`);
  }
}

function setupSnapshots(dir, version) {
  const snapshotDir = path.join(dir, "db", "Db");
  fs.mkdirSync(snapshotDir, { recursive: true });
  for (let v = 1; v < version; v++) {
    const p = path.join(snapshotDir, `V${v}.elm`);
    if (!fs.existsSync(p)) {
      fs.writeFileSync(
        p,
        `module Db.V${v} exposing (Db)\n\ntype alias Db =\n    { counter : Int\n    }\n`
      );
    }
  }
}

describe("elm-pages db init", () => {
  it("creates Db.elm and V1 migration in first source-directory from script/elm.json", async () => {
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
    expect(content).not.toContain("init : Db");

    // V1 migration file created
    const v1Path = path.join(tmpDir, "db", "Db", "Migrate", "V1.elm");
    expect(fs.existsSync(v1Path)).toBe(true);
    const v1Content = fs.readFileSync(v1Path, "utf8");
    expect(v1Content).toContain("seed : () -> Db.Db");

    // Schema version derived from V1.elm
    const version = await readSchemaVersion(tmpDir);
    expect(version).toBe(1);
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

  it("adds db artifacts to .gitignore", async () => {
    fs.writeFileSync(
      path.join(tmpDir, "elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );

    await init();

    const gitignorePath = path.join(tmpDir, ".gitignore");
    expect(fs.existsSync(gitignorePath)).toBe(true);
    const gitignore = fs.readFileSync(gitignorePath, "utf8");
    expect(gitignore).toContain("db.bin");
    expect(gitignore).toContain("db.bin.lock");
    expect(gitignore).toContain("db.bin.backup");
    expect(gitignore).toContain("db/schema-history/");
  });

  it("does not duplicate db ignore entries", async () => {
    fs.writeFileSync(
      path.join(tmpDir, "elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.writeFileSync(path.join(tmpDir, ".gitignore"), "node_modules/\ndb.bin\n");

    await init();
    await init();

    const lines = fs
      .readFileSync(path.join(tmpDir, ".gitignore"), "utf8")
      .split(/\r?\n/)
      .filter(Boolean);
    const dbBinCount = lines.filter((line) => line === "db.bin").length;
    const dbLockCount = lines.filter((line) => line === "db.bin.lock").length;
    const dbBackupCount = lines.filter((line) => line === "db.bin.backup").length;
    const schemaHistoryCount = lines.filter((line) => line === "db/schema-history/").length;
    expect(dbBinCount).toBe(1);
    expect(dbLockCount).toBe(1);
    expect(dbBackupCount).toBe(1);
    expect(schemaHistoryCount).toBe(1);
  });
});

describe("elm-pages db migrate", () => {
  const dbSource = `module Db exposing (Db)

type alias Db =
    { counter : Int
    }
`;

  function setupV1Migration() {
    const migrateDir = path.join(tmpDir, "db", "Db", "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });
    fs.writeFileSync(
      path.join(migrateDir, "V1.elm"),
      `module Db.Migrate.V1 exposing (migrate, seed)

import Db


seed : () -> Db.Db
seed () =
    { counter = 0
    }


migrate : () -> Db.Db
migrate =
    seed
`
    );
  }

  it("creates snapshot and stub", async () => {
    // Set up Db.elm
    fs.mkdirSync(path.join(tmpDir, "script"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "script/elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.mkdirSync(path.join(tmpDir, "script/src"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "script/src/Db.elm"), dbSource);
    setupV1Migration();

    await migrate();

    // Snapshot V1.elm
    const snapshotPath = path.join(tmpDir, "db", "Db", "V1.elm");
    expect(fs.existsSync(snapshotPath)).toBe(true);
    const snapshotContent = fs.readFileSync(snapshotPath, "utf8");
    expect(snapshotContent).toContain("module Db.V1 exposing");

    // Migration stub V2.elm
    const stubPath = path.join(tmpDir, "db", "Db", "Migrate", "V2.elm");
    expect(fs.existsSync(stubPath)).toBe(true);

    // Schema version bumped to 2 (V2.elm now exists)
    const version = await readSchemaVersion(tmpDir);
    expect(version).toBe(2);
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
    setupV1Migration();

    // Create pending migration: db.bin at V1, schema at V2
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );
    setupSchemaVersion(tmpDir, 2);

    const logSpy = vi.spyOn(console, "log");
    await migrate();

    const logOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(logOutput).toContain("Pending migration");
    logSpy.mockRestore();
  });

  it("refuses stale snapshot scaffold when Db.elm changed before snapshotting", async () => {
    fs.mkdirSync(path.join(tmpDir, "script"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "script/elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.mkdirSync(path.join(tmpDir, "script/src"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "script/src/Db.elm"), dbSource);
    setupV1Migration();

    const oldHash = await computeSchemaHash(path.join(tmpDir, "script/src/Db.elm"));
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(oldHash, 1, Buffer.from([1, 2, 3]))
    );

    // User edits Db.elm before running db migrate
    fs.writeFileSync(
      path.join(tmpDir, "script/src/Db.elm"),
      `module Db exposing (Db)

type alias Db =
    { counter : Int
    , name : String
    }
`
    );

    const logSpy = vi.spyOn(console, "log");
    await migrate();

    const logOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(logOutput).toContain("Cannot create migration files yet.");
    expect(logOutput).toContain("Missing: db/schema-history/");
    expect(process.exitCode).toBe(1);
    expect(fs.existsSync(path.join(tmpDir, "db", "Db", "V1.elm"))).toBe(false);
    logSpy.mockRestore();
  });

  it("allows stale snapshot scaffold when --force-stale-snapshot is set", async () => {
    fs.mkdirSync(path.join(tmpDir, "script"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "script/elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.mkdirSync(path.join(tmpDir, "script/src"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "script/src/Db.elm"), dbSource);
    setupV1Migration();

    const oldHash = await computeSchemaHash(path.join(tmpDir, "script/src/Db.elm"));
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(oldHash, 1, Buffer.from([1, 2, 3]))
    );

    fs.writeFileSync(
      path.join(tmpDir, "script/src/Db.elm"),
      `module Db exposing (Db)

type alias Db =
    { counter : Int
    , name : String
    }
`
    );

    await migrate({ forceStaleSnapshot: true });

    const snapshotPath = path.join(tmpDir, "db", "Db", "V1.elm");
    expect(fs.existsSync(snapshotPath)).toBe(true);
    const snapshotContent = fs.readFileSync(snapshotPath, "utf8");
    expect(snapshotContent).toContain(", name : String");
    expect(process.exitCode).not.toBe(1);
  });
});

describe("elm-pages db status", () => {
  const dbSource = `module Db exposing (Db)

type alias Db =
    { counter : Int
    }
`;

  function setupProject() {
    fs.mkdirSync(path.join(tmpDir, "script"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "script/elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.mkdirSync(path.join(tmpDir, "script/src"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "script/src/Db.elm"), dbSource);
  }

  it("shows up-to-date when db.bin matches schema version", async () => {
    setupProject();
    const testHash = crypto.createHash("sha256").update("test").digest("hex");
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 2, Buffer.from([1, 2, 3]))
    );
    setupSchemaVersion(tmpDir, 2);
    setupSnapshots(tmpDir, 2);

    const logSpy = vi.spyOn(console, "log");
    await status();

    const logOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(logOutput).toContain("up to date");
    expect(process.exitCode).not.toBe(1);
    logSpy.mockRestore();
  });

  it("shows pending migration chain with unimplemented stub", async () => {
    setupProject();
    const testHash = crypto.createHash("sha256").update("test").digest("hex");
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );

    // Create snapshot and unimplemented stub
    fs.mkdirSync(path.join(tmpDir, "db", "Db", "Migrate"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "db", "Db", "V1.elm"),
      "module Db.V1 exposing (Db)\ntype alias Db = { counter : Int }"
    );
    fs.writeFileSync(
      path.join(tmpDir, "db", "Db", "Migrate", "V1.elm"),
      "module Db.Migrate.V1 exposing (..)\nstub = ()\n"
    );
    fs.writeFileSync(
      path.join(tmpDir, "db", "Db", "Migrate", "V2.elm"),
      "module Db.Migrate.V2 exposing (migrate)\ntodo_implement_migration"
    );

    const logSpy = vi.spyOn(console, "log");
    await status();

    const logOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(logOutput).toMatch(/V1 → V2/);
    expect(logOutput).toContain("pending");
    expect(logOutput).toContain("unimplemented stub");
    expect(logOutput).toContain("Implement the migration stubs");
    logSpy.mockRestore();
  });

  it("reports a missing initial seed when schema version is 1 and V1 is missing", async () => {
    setupProject();

    const logSpy = vi.spyOn(console, "log");
    await status();

    const logOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(logOutput).toContain("Initial seed:    INCOMPLETE");
    expect(logOutput).toContain("Seed chain:");
    expect(logOutput).toMatch(/V0 → V1/);
    expect(logOutput).toContain("missing");
    expect(logOutput).toContain("fresh install can initialize safely");
    expect(process.exitCode).toBe(1);
    logSpy.mockRestore();
  });

  it("shows initial seed ready when schema version is 1", async () => {
    setupProject();
    setupSchemaVersion(tmpDir, 1);

    const logSpy = vi.spyOn(console, "log");
    await status();

    const logOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(logOutput).toContain("Initial seed:    ready");
    expect(logOutput).not.toContain("Migration chain");
    expect(process.exitCode).not.toBe(1);
    logSpy.mockRestore();
  });
});

describe("exit codes", () => {
  const dbSource = `module Db exposing (Db)

type alias Db =
    { counter : Int
    }
`;

  function setupProject() {
    fs.mkdirSync(path.join(tmpDir, "script"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "script/elm.json"),
      JSON.stringify({ "source-directories": ["src"] })
    );
    fs.mkdirSync(path.join(tmpDir, "script/src"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "script/src/Db.elm"), dbSource);
  }

  it("db status exits 1 when migrations are pending", async () => {
    setupProject();
    const testHash = crypto.createHash("sha256").update("test").digest("hex");
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );
    setupSchemaVersion(tmpDir, 2);

    const logSpy = vi.spyOn(console, "log");
    await status();
    logSpy.mockRestore();

    expect(process.exitCode).toBe(1);
  });

  it("db status exits 0 when up-to-date", async () => {
    setupProject();
    const testHash = crypto.createHash("sha256").update("test").digest("hex");
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 2, Buffer.from([1, 2, 3]))
    );
    setupSchemaVersion(tmpDir, 2);
    setupSnapshots(tmpDir, 2);

    const logSpy = vi.spyOn(console, "log");
    await status();
    logSpy.mockRestore();

    expect(process.exitCode).not.toBe(1);
  });

  it("db migrate Path C exits 1", async () => {
    setupProject();
    const testHash = crypto.createHash("sha256").update("test").digest("hex");
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );
    setupSchemaVersion(tmpDir, 2);

    const logSpy = vi.spyOn(console, "log");
    await migrate();
    logSpy.mockRestore();

    expect(process.exitCode).toBe(1);
  });
});
