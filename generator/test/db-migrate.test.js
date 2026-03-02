/**
 * Tests for db-migrate.js — migration snapshot/stub generation and orchestration.
 */

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as crypto from "node:crypto";
import {
  rewriteDbModuleToSnapshot,
  generateMigrationStub,
  checkPendingMigration,
  createSnapshot,
  generateMigrateChain,
  writeMigrateChain,
  detectMigrationNeeded,
  validateMigrationChain,
  prepareMigrationSourceDirs,
} from "../src/db-migrate.js";
import { buildDbBin } from "../src/db-bin-format.js";
import { writeSchemaVersion } from "../src/db-schema.js";

let tmpDir;

beforeEach(async () => {
  tmpDir = await fs.promises.mkdtemp(
    path.join(os.tmpdir(), "db-migrate-test-")
  );
});

afterEach(async () => {
  await fs.promises.rm(tmpDir, { recursive: true });
});

// --- Section A1: rewriteDbModuleToSnapshot ---

describe("rewriteDbModuleToSnapshot", () => {
  it("rewrites module declaration from Db to Db.V{N} and preserves body", () => {
    const source = `module Db exposing (Db, init)

type alias Db =
    { counter : Int
    }

init : Db
init =
    { counter = 0
    }
`;
    expect(rewriteDbModuleToSnapshot(source, 1)).toBe(`module Db.V1 exposing (Db, init)

type alias Db =
    { counter : Int
    }

init : Db
init =
    { counter = 0
    }
`);
  });

  it("handles exposing (..) variant", () => {
    const source = `module Db exposing (..)

type alias Db = { name : String }
`;
    expect(rewriteDbModuleToSnapshot(source, 1)).toBe(`module Db.V1 exposing (..)

type alias Db = { name : String }
`);
  });

  it("uses the given version number", () => {
    const source = `module Db exposing (Db, init)

type alias Db = { x : Int }
`;
    expect(rewriteDbModuleToSnapshot(source, 2)).toBe(`module Db.V2 exposing (Db, init)

type alias Db = { x : Int }
`);
  });
});

// --- Section A2: generateMigrationStub ---

describe("generateMigrationStub", () => {
  it("generates V1 seed stub for V0 -> V1 migration", () => {
    expect(generateMigrationStub(0, 1)).toBe(`module Db.Migrate.V1 exposing (migrate, seed)

import Db


seed : () -> Db.Db
seed () =
    todo_implement_seed_V1


migrate : () -> Db.Db
migrate =
    seed
`);
  });

  it("generates V2 stub for V1 -> V2 migration", () => {
    expect(generateMigrationStub(1, 2)).toBe(`module Db.Migrate.V2 exposing (migrate, seed)

import Db
import Db.V1


migrate : Db.V1.Db -> Db.Db
migrate old =
    todo_implement_migration_V1_to_V2


seed : Db.V1.Db -> Db.Db
seed old =
    migrate old
`);
  });

  it("generates V3 stub for V2 -> V3 migration", () => {
    expect(generateMigrationStub(2, 3)).toBe(`module Db.Migrate.V3 exposing (migrate, seed)

import Db
import Db.V2


migrate : Db.V2.Db -> Db.Db
migrate old =
    todo_implement_migration_V2_to_V3


seed : Db.V2.Db -> Db.Db
seed old =
    migrate old
`);
  });
});

// --- Section A4: checkPendingMigration ---

describe("checkPendingMigration", () => {
  const testHash = crypto.createHash("sha256").update("test").digest("hex");

  it("returns pending:true when db.bin version < schema version", async () => {
    // Create db.bin at version 1
    const dbBin = buildDbBin(testHash, 1, Buffer.from([1, 2, 3]));
    fs.writeFileSync(path.join(tmpDir, "db.bin"), dbBin);
    // Set schema version to 2
    await writeSchemaVersion(tmpDir, 2);

    const result = await checkPendingMigration(tmpDir);
    expect(result.pending).toBe(true);
    expect(result.dbBinVersion).toBe(1);
    expect(result.schemaVersion).toBe(2);
  });

  it("returns pending:false when versions match", async () => {
    const dbBin = buildDbBin(testHash, 2, Buffer.from([1, 2, 3]));
    fs.writeFileSync(path.join(tmpDir, "db.bin"), dbBin);
    await writeSchemaVersion(tmpDir, 2);

    const result = await checkPendingMigration(tmpDir);
    expect(result.pending).toBe(false);
  });

  it("returns pending:false when no db.bin exists", async () => {
    await writeSchemaVersion(tmpDir, 2);

    const result = await checkPendingMigration(tmpDir);
    expect(result.pending).toBe(false);
  });
});

// --- Section A3: createSnapshot ---

describe("createSnapshot", () => {
  const dbSource = `module Db exposing (Db, init)

type alias Db =
    { counter : Int
    }

init : Db
init =
    { counter = 0
    }
`;

  it("writes snapshot V1.elm matching rewriteDbModuleToSnapshot output", async () => {
    await writeSchemaVersion(tmpDir, 1);

    await createSnapshot(tmpDir, dbSource, 1);

    const snapshotPath = path.join(tmpDir, ".elm-pages-db", "Db", "V1.elm");
    const content = fs.readFileSync(snapshotPath, "utf8");
    expect(content).toBe(rewriteDbModuleToSnapshot(dbSource, 1));
  });

  it("writes migration stub V2.elm matching generateMigrationStub output", async () => {
    await writeSchemaVersion(tmpDir, 1);

    await createSnapshot(tmpDir, dbSource, 1);

    const stubPath = path.join(
      tmpDir,
      ".elm-pages-db",
      "Db",
      "Migrate",
      "V2.elm"
    );
    const content = fs.readFileSync(stubPath, "utf8");
    expect(content).toBe(generateMigrationStub(1, 2));
  });

  it("bumps schema version from 1 to 2", async () => {
    await writeSchemaVersion(tmpDir, 1);

    await createSnapshot(tmpDir, dbSource, 1);

    const versionPath = path.join(
      tmpDir,
      ".elm-pages-db",
      "schema-version.json"
    );
    const versionData = JSON.parse(fs.readFileSync(versionPath, "utf8"));
    expect(versionData.version).toBe(2);
  });

});

// --- Section B1-B2: generateMigrateChain ---

describe("generateMigrateChain", () => {
  it("single migration (target V2) produces correct Elm module", () => {
    expect(generateMigrateChain(2)).toMatchSnapshot();
  });

  it("multi-step migration (target V3) produces correct Elm module", () => {
    expect(generateMigrateChain(3)).toMatchSnapshot();
  });

  it("four-step migration (target V4) produces correct Elm module", () => {
    expect(generateMigrateChain(4)).toMatchSnapshot();
  });
});

// --- Section B3: writeMigrateChain ---

describe("writeMigrateChain", () => {
  it("creates .elm-pages-db/MigrateChain.elm matching generateMigrateChain output", async () => {
    await writeMigrateChain(tmpDir, 2);

    const chainPath = path.join(tmpDir, ".elm-pages-db", "MigrateChain.elm");
    const content = fs.readFileSync(chainPath, "utf8");
    expect(content).toBe(generateMigrateChain(2));
  });
});

// --- Section C1: detectMigrationNeeded ---

describe("detectMigrationNeeded", () => {
  const testHash = crypto.createHash("sha256").update("test").digest("hex");

  it("returns up-to-date when versions match", async () => {
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 2, Buffer.from([1, 2, 3]))
    );
    await writeSchemaVersion(tmpDir, 2);

    const result = await detectMigrationNeeded(tmpDir);
    expect(result.action).toBe("up-to-date");
  });

  it("returns migrate when db.bin < schema", async () => {
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );
    await writeSchemaVersion(tmpDir, 3);

    const result = await detectMigrationNeeded(tmpDir);
    expect(result.action).toBe("migrate");
    expect(result.fromVersion).toBe(1);
    expect(result.toVersion).toBe(3);
  });

  it("returns no-db when no db.bin exists", async () => {
    await writeSchemaVersion(tmpDir, 2);

    const result = await detectMigrationNeeded(tmpDir);
    expect(result.action).toBe("no-db");
  });

  it("returns error when db.bin > schema", async () => {
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 5, Buffer.from([1, 2, 3]))
    );
    await writeSchemaVersion(tmpDir, 2);

    const result = await detectMigrationNeeded(tmpDir);
    expect(result.action).toBe("error");
  });
});

// --- Section C2: validateMigrationChain ---

describe("validateMigrationChain", () => {
  it("returns valid:true when all files exist and have no sentinel", async () => {
    const dbDir = path.join(tmpDir, ".elm-pages-db", "Db");
    const migrateDir = path.join(dbDir, "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });

    // Snapshot V1
    fs.writeFileSync(
      path.join(dbDir, "V1.elm"),
      "module Db.V1 exposing (Db)\ntype alias Db = { x : Int }\n"
    );
    // Migration V2 (implemented, no sentinel)
    fs.writeFileSync(
      path.join(migrateDir, "V2.elm"),
      "module Db.Migrate.V2 exposing (migrate, seed)\nimport Db\nimport Db.V1\nmigrate old = { x = old.x + 1 }\nseed old = migrate old\n"
    );

    const result = await validateMigrationChain(tmpDir, 1, 2);
    expect(result.valid).toBe(true);
  });

  it("reports missing snapshot files", async () => {
    const migrateDir = path.join(
      tmpDir,
      ".elm-pages-db",
      "Db",
      "Migrate"
    );
    fs.mkdirSync(migrateDir, { recursive: true });
    // Migration V2 exists but snapshot V1 does not
    fs.writeFileSync(
      path.join(migrateDir, "V2.elm"),
      "module Db.Migrate.V2 exposing (migrate, seed)\nmigrate old = { x = 0 }\nseed old = migrate old\n"
    );

    const result = await validateMigrationChain(tmpDir, 1, 2);
    expect(result.valid).toBe(false);
    expect(result.missingFiles).toContain("Db/V1.elm");
  });

  it("reports missing migration files", async () => {
    const dbDir = path.join(tmpDir, ".elm-pages-db", "Db");
    fs.mkdirSync(dbDir, { recursive: true });
    // Snapshot V1 exists but migration V2 does not
    fs.writeFileSync(path.join(dbDir, "V1.elm"), "module Db.V1 exposing (Db)");

    const result = await validateMigrationChain(tmpDir, 1, 2);
    expect(result.valid).toBe(false);
    expect(result.missingFiles).toContain("Db/Migrate/V2.elm");
  });

  it("reports unimplemented migrations (sentinel present)", async () => {
    const dbDir = path.join(tmpDir, ".elm-pages-db", "Db");
    const migrateDir = path.join(dbDir, "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });

    fs.writeFileSync(path.join(dbDir, "V1.elm"), "module Db.V1 exposing (Db)");
    fs.writeFileSync(
      path.join(migrateDir, "V2.elm"),
      "module Db.Migrate.V2 exposing (migrate, seed)\nmigrate old = todo_implement_migration_V1_to_V2\nseed old = migrate old\n"
    );

    const result = await validateMigrationChain(tmpDir, 1, 2);
    expect(result.valid).toBe(false);
    expect(result.unimplemented).toContain("Db/Migrate/V2.elm");
  });

  it("reports unimplemented V1 seed (todo_implement_seed sentinel)", async () => {
    const migrateDir = path.join(tmpDir, ".elm-pages-db", "Db", "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });

    fs.writeFileSync(
      path.join(migrateDir, "V1.elm"),
      "module Db.Migrate.V1 exposing (migrate, seed)\nseed () = todo_implement_seed_V1\nmigrate = seed\n"
    );

    const result = await validateMigrationChain(tmpDir, 0, 1);
    expect(result.valid).toBe(false);
    expect(result.unimplemented).toContain("Db/Migrate/V1.elm");
  });

  it("skips V0 snapshot check (virtual V0 has no file)", async () => {
    const migrateDir = path.join(tmpDir, ".elm-pages-db", "Db", "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });

    fs.writeFileSync(
      path.join(migrateDir, "V1.elm"),
      "module Db.Migrate.V1 exposing (migrate, seed)\nimport Db\nseed () = { counter = 0 }\nmigrate = seed\n"
    );

    const result = await validateMigrationChain(tmpDir, 0, 1);
    expect(result.valid).toBe(true);
  });
});

// --- Section C3: prepareMigrationSourceDirs ---

describe("prepareMigrationSourceDirs", () => {
  it("adds .elm-pages-db to elm.json source-directories", async () => {
    const compileDir = path.join(tmpDir, "compile");
    fs.mkdirSync(compileDir, { recursive: true });
    fs.writeFileSync(
      path.join(compileDir, "elm.json"),
      JSON.stringify({
        type: "application",
        "source-directories": ["src", ".elm-pages"],
      })
    );

    const restore = await prepareMigrationSourceDirs(compileDir, tmpDir);

    const elmJson = JSON.parse(
      fs.readFileSync(path.join(compileDir, "elm.json"), "utf8")
    );
    // Should include a path to .elm-pages-db relative to the compile dir
    const sourceDirs = elmJson["source-directories"];
    expect(sourceDirs.some((d) => d.includes(".elm-pages-db"))).toBe(true);

    // Restore should remove it
    await restore();
    const restored = JSON.parse(
      fs.readFileSync(path.join(compileDir, "elm.json"), "utf8")
    );
    expect(restored["source-directories"]).toEqual(["src", ".elm-pages"]);
  });
});

// --- Section F1: Integration test for detectMigrationNeeded + validateMigrationChain ---

describe("migration detection + validation integration", () => {
  const testHash = crypto.createHash("sha256").update("test").digest("hex");

  it("detects migrate needed and validates a complete chain", async () => {
    // Set up db.bin at V1, schema at V2
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );
    await writeSchemaVersion(tmpDir, 2);

    // Create valid chain files
    const dbDir = path.join(tmpDir, ".elm-pages-db", "Db");
    const migrateDir = path.join(dbDir, "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });
    fs.writeFileSync(
      path.join(dbDir, "V1.elm"),
      "module Db.V1 exposing (Db)\ntype alias Db = { counter : Int }\n"
    );
    fs.writeFileSync(
      path.join(migrateDir, "V2.elm"),
      "module Db.Migrate.V2 exposing (migrate, seed)\nimport Db\nimport Db.V1\nmigrate old = { counter = old.counter, name = \"\" }\nseed old = migrate old\n"
    );

    const detection = await detectMigrationNeeded(tmpDir);
    expect(detection.action).toBe("migrate");
    expect(detection.fromVersion).toBe(1);
    expect(detection.toVersion).toBe(2);

    const validation = await validateMigrationChain(
      tmpDir,
      detection.fromVersion,
      detection.toVersion
    );
    expect(validation.valid).toBe(true);
  });

  it("detects migrate needed but fails validation with unimplemented stub", async () => {
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );
    await writeSchemaVersion(tmpDir, 2);

    // Create chain files with unimplemented sentinel
    const dbDir = path.join(tmpDir, ".elm-pages-db", "Db");
    const migrateDir = path.join(dbDir, "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });
    fs.writeFileSync(
      path.join(dbDir, "V1.elm"),
      "module Db.V1 exposing (Db)\ntype alias Db = { counter : Int }\n"
    );
    fs.writeFileSync(
      path.join(migrateDir, "V2.elm"),
      "module Db.Migrate.V2 exposing (migrate, seed)\nmigrate old = todo_implement_migration_V1_to_V2\nseed old = migrate old\n"
    );

    const detection = await detectMigrationNeeded(tmpDir);
    expect(detection.action).toBe("migrate");

    const validation = await validateMigrationChain(
      tmpDir,
      detection.fromVersion,
      detection.toVersion
    );
    expect(validation.valid).toBe(false);
    expect(validation.unimplemented.length).toBe(1);
  });
});
