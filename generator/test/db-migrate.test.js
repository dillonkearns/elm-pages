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
  it("rewrites 'module Db exposing (Db, init)' to 'module Db.V1 exposing (Db, init)'", () => {
    const source = `module Db exposing (Db, init)

type alias Db =
    { counter : Int
    }

init : Db
init =
    { counter = 0
    }
`;
    const result = rewriteDbModuleToSnapshot(source, 1);
    expect(result).toContain("module Db.V1 exposing (Db, init)");
    // Body should be preserved
    expect(result).toContain("type alias Db =");
    expect(result).toContain("{ counter : Int");
  });

  it("rewrites 'module Db exposing (..)' variant", () => {
    const source = `module Db exposing (..)

type alias Db = { name : String }
`;
    const result = rewriteDbModuleToSnapshot(source, 1);
    expect(result).toContain("module Db.V1 exposing (..)");
  });

  it("rewrites to V2 when version is 2", () => {
    const source = `module Db exposing (Db, init)

type alias Db = { x : Int }
`;
    const result = rewriteDbModuleToSnapshot(source, 2);
    expect(result).toContain("module Db.V2 exposing (Db, init)");
  });

  it("preserves the body unchanged", () => {
    const source = `module Db exposing (Db, Todo, init)

type alias Db =
    { todos : List Todo
    , nextId : Int
    }

type alias Todo =
    { id : Int
    , title : String
    , completed : Bool
    }

init : Db
init =
    { todos = []
    , nextId = 1
    }
`;
    const result = rewriteDbModuleToSnapshot(source, 1);
    // First line changed
    expect(result.startsWith("module Db.V1 exposing (Db, Todo, init)")).toBe(
      true
    );
    // Rest preserved
    expect(result).toContain("type alias Todo =");
    expect(result).toContain("{ id : Int");
    expect(result).toContain("init : Db");
  });
});

// --- Section A2: generateMigrationStub ---

describe("generateMigrationStub", () => {
  it("generates V2 stub for V1 -> V2 migration", () => {
    const stub = generateMigrationStub(1, 2);
    expect(stub).toContain("module Db.Migrate.V2 exposing (db)");
    expect(stub).toContain("import Db.V1");
    expect(stub).toContain("import Db");
    expect(stub).toContain("db : Db.V1.Db -> Db.Db");
    expect(stub).toContain("todo_implement_migration_V1_to_V2");
  });

  it("generates V3 stub for V2 -> V3 migration", () => {
    const stub = generateMigrationStub(2, 3);
    expect(stub).toContain("module Db.Migrate.V3 exposing (db)");
    expect(stub).toContain("import Db.V2");
    expect(stub).toContain("import Db");
    expect(stub).toContain("db : Db.V2.Db -> Db.Db");
    expect(stub).toContain("todo_implement_migration_V2_to_V3");
  });

  it("produces valid Elm that would compile except for the sentinel", () => {
    const stub = generateMigrationStub(1, 2);
    // Should have proper Elm structure
    expect(stub).toMatch(/^module Db\.Migrate\.V2 exposing/m);
    // Should have a function body (not just a type signature)
    expect(stub).toContain("db old =");
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

  it("writes snapshot V1.elm with rewritten module", async () => {
    await writeSchemaVersion(tmpDir, 1);

    await createSnapshot(tmpDir, dbSource, 1);

    const snapshotPath = path.join(tmpDir, ".elm-pages-db", "Db", "V1.elm");
    expect(fs.existsSync(snapshotPath)).toBe(true);
    const content = fs.readFileSync(snapshotPath, "utf8");
    expect(content).toContain("module Db.V1 exposing (Db, init)");
    expect(content).toContain("{ counter : Int");
  });

  it("writes migration stub V2.elm", async () => {
    await writeSchemaVersion(tmpDir, 1);

    await createSnapshot(tmpDir, dbSource, 1);

    const stubPath = path.join(
      tmpDir,
      ".elm-pages-db",
      "Db",
      "Migrate",
      "V2.elm"
    );
    expect(fs.existsSync(stubPath)).toBe(true);
    const content = fs.readFileSync(stubPath, "utf8");
    expect(content).toContain("module Db.Migrate.V2 exposing (db)");
    expect(content).toContain("import Db.V1");
    expect(content).toContain("todo_implement_migration_V1_to_V2");
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

  it("refuses when a pending migration exists", async () => {
    const testHash = crypto.createHash("sha256").update("test").digest("hex");
    // db.bin at version 1, schema at version 2 = pending migration
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(testHash, 1, Buffer.from([1, 2, 3]))
    );
    await writeSchemaVersion(tmpDir, 2);

    await expect(createSnapshot(tmpDir, dbSource, 2)).rejects.toThrow(
      /pending migration/i
    );
  });
});

// --- Section B1: generateMigrateChain — single migration (V1→V2) ---

describe("generateMigrateChain — single migration", () => {
  it("generates module MigrateChain exposing (run)", () => {
    const chain = generateMigrateChain(2);
    expect(chain).toContain("module MigrateChain exposing (run)");
  });

  it("imports Db.V1, Db.Migrate.V2 as MigrateV2, Db, and Lamdera.Wire3", () => {
    const chain = generateMigrateChain(2);
    expect(chain).toContain("import Db.V1");
    expect(chain).toContain("import Db.Migrate.V2 as MigrateV2");
    expect(chain).toContain("import Db");
    expect(chain).toContain("import Lamdera.Wire3 as Wire");
  });

  it("has a case branch for version 1 that decodes with Db.V1.w3_decode_Db", () => {
    const chain = generateMigrateChain(2);
    expect(chain).toMatch(/1\s*->/);
    expect(chain).toContain("Db.V1.w3_decode_Db");
  });

  it("applies MigrateV2.db in the migration chain", () => {
    const chain = generateMigrateChain(2);
    expect(chain).toContain("MigrateV2.db");
  });

  it("re-encodes with Db.w3_encode_Db for saving", () => {
    const chain = generateMigrateChain(2);
    expect(chain).toContain("Db.w3_encode_Db");
  });

  it("uses BackendTask.Http with elm-pages-internal:// URLs for I/O, NOT LamderaDb", () => {
    const chain = generateMigrateChain(2);
    expect(chain).toContain("elm-pages-internal://");
    expect(chain).toContain("BackendTask.Http.request");
    expect(chain).toContain("BackendTask.allowFatal");
    expect(chain).not.toContain("BackendTask.Internal.Request");
    expect(chain).not.toContain("LamderaDb");
  });

  it("uses db-migrate-read and db-migrate-write handlers", () => {
    const chain = generateMigrateChain(2);
    expect(chain).toContain("db-migrate-read");
    expect(chain).toContain("db-migrate-write");
  });
});

// --- Section B2: generateMigrateChain — multi-step (V1→V2→V3) ---

describe("generateMigrateChain — multi-step migration", () => {
  it("imports Db.V1, Db.V2, MigrateV2, MigrateV3", () => {
    const chain = generateMigrateChain(3);
    expect(chain).toContain("import Db.V1");
    expect(chain).toContain("import Db.V2");
    expect(chain).toContain("import Db.Migrate.V2 as MigrateV2");
    expect(chain).toContain("import Db.Migrate.V3 as MigrateV3");
  });

  it("has case branches for both versions 1 and 2", () => {
    const chain = generateMigrateChain(3);
    expect(chain).toMatch(/1\s*->/);
    expect(chain).toMatch(/2\s*->/);
  });

  it("chains V1→V2→V3: migrateFromV1 applies MigrateV2.db then feeds to migrateFromV2", () => {
    const chain = generateMigrateChain(3);
    // migrateFromV1 should call MigrateV2.db and then chain to migrateFromV2
    expect(chain).toContain("migrateFromV1");
    expect(chain).toContain("migrateFromV2");
    // migrateFromV2 should apply MigrateV3.db
    expect(chain).toContain("MigrateV3.db");
  });
});

// --- Section B3: writeMigrateChain ---

describe("writeMigrateChain", () => {
  it("creates .elm-pages-db/MigrateChain.elm with correct content", async () => {
    await writeMigrateChain(tmpDir, 2);

    const chainPath = path.join(tmpDir, ".elm-pages-db", "MigrateChain.elm");
    expect(fs.existsSync(chainPath)).toBe(true);
    const content = fs.readFileSync(chainPath, "utf8");
    expect(content).toContain("module MigrateChain exposing (run)");
    expect(content).toContain("import Db.V1");
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
      "module Db.Migrate.V2 exposing (db)\nimport Db\nimport Db.V1\ndb old = { x = old.x + 1 }\n"
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
      "module Db.Migrate.V2 exposing (db)\ndb old = { x = 0 }\n"
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
      "module Db.Migrate.V2 exposing (db)\ndb old = todo_implement_migration_V1_to_V2\n"
    );

    const result = await validateMigrationChain(tmpDir, 1, 2);
    expect(result.valid).toBe(false);
    expect(result.unimplemented).toContain("Db/Migrate/V2.elm");
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
      "module Db.Migrate.V2 exposing (db)\nimport Db\nimport Db.V1\ndb old = { counter = old.counter, name = \"\" }\n"
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
      "module Db.Migrate.V2 exposing (db)\ndb old = todo_implement_migration_V1_to_V2\n"
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
