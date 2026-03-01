/**
 * End-to-end integration tests for the full migration user flow.
 *
 * These tests exercise the complete JS infrastructure for migrations,
 * simulating the user's workflow:
 *   1. Create project with Db.elm and seed db.bin
 *   2. Run `elm-pages db migrate` to create snapshot/stub/chain
 *   3. Implement the migration stub
 *   4. Detection + validation confirms migration is ready
 *   5. render.js handlers read old db.bin and write migrated db.bin
 *   6. Verify the new db.bin has correct version and data
 *
 * Does not compile actual Elm — tests the full JS slice end-to-end.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as crypto from "node:crypto";

import { migrate, status } from "../src/commands/db.js";
import {
  detectMigrationNeeded,
  validateMigrationChain,
  writeMigrateChain,
  createSnapshot,
  prepareMigrationSourceDirs,
} from "../src/db-migrate.js";
import {
  parseDbBinHeader,
  buildDbBin,
  DB_HEADER_SIZE,
} from "../src/db-bin-format.js";
import {
  readSchemaVersion,
  writeSchemaVersion,
  computeSchemaHash,
} from "../src/db-schema.js";

let tmpDir;
let originalCwd;

const dbSourceV1 = `module Db exposing (Db, init)


type alias Db =
    { counter : Int
    }


init : Db
init =
    { counter = 0
    }
`;

const dbSourceV2 = `module Db exposing (Db, init)


type alias Db =
    { counter : Int
    , name : String
    }


init : Db
init =
    { counter = 0
    , name = ""
    }
`;

const dbSourceV3 = `module Db exposing (Db, init)


type alias Db =
    { counter : Int
    , name : String
    , active : Bool
    }


init : Db
init =
    { counter = 0
    , name = ""
    , active = True
    }
`;

/**
 * Set up a minimal project structure that mirrors a real elm-pages project.
 * CWD is set to tmpDir (simulating user running from project root).
 * Db.elm lives in script/src/ (projectDirectory = script/).
 */
function setupProject(dbSource) {
  const scriptDir = path.join(tmpDir, "script");
  const srcDir = path.join(scriptDir, "src");
  fs.mkdirSync(srcDir, { recursive: true });
  fs.writeFileSync(
    path.join(scriptDir, "elm.json"),
    JSON.stringify({
      type: "application",
      "source-directories": ["src"],
      "elm-version": "0.19.1",
      dependencies: { direct: {}, indirect: {} },
      "test-dependencies": { direct: {}, indirect: {} },
    })
  );
  fs.writeFileSync(path.join(srcDir, "Db.elm"), dbSource);
}

/**
 * Create a db.bin at CWD with known Wire3 data at a specific version.
 */
function seedDbBin(schemaHash, version, wire3Data) {
  const dbBin = buildDbBin(schemaHash, version, wire3Data);
  fs.writeFileSync(path.join(tmpDir, "db.bin"), dbBin);
  return dbBin;
}

beforeEach(async () => {
  tmpDir = await fs.promises.mkdtemp(
    path.join(os.tmpdir(), "db-e2e-test-")
  );
  originalCwd = process.cwd();
  process.chdir(tmpDir);
});

afterEach(async () => {
  process.chdir(originalCwd);
  await fs.promises.rm(tmpDir, { recursive: true });
});

describe("E2E: single migration (V1 → V2)", () => {
  it("full flow: seed → migrate → implement → detect → validate → read → write", async () => {
    // === Step 1: Set up project with V1 schema and seeded db.bin ===
    setupProject(dbSourceV1);

    const hashV1 = await computeSchemaHash(
      path.join(tmpDir, "script/src/Db.elm")
    );
    const wire3DataV1 = Buffer.from([0x01, 0x02, 0x03, 0x04]);
    seedDbBin(hashV1, 1, wire3DataV1);
    await writeSchemaVersion(tmpDir, 1);

    // Verify initial state
    const initialDbBin = parseDbBinHeader(
      fs.readFileSync(path.join(tmpDir, "db.bin"))
    );
    expect(initialDbBin.schemaVersion).toBe(1);
    expect(initialDbBin.schemaHashHex).toBe(hashV1);
    expect([...initialDbBin.wire3Data]).toEqual([0x01, 0x02, 0x03, 0x04]);

    // === Step 2: User runs `elm-pages db migrate` ===
    await migrate();

    // Verify snapshot, stub, and chain files created
    const snapshotPath = path.join(tmpDir, ".elm-pages-db", "Db", "V1.elm");
    expect(fs.existsSync(snapshotPath)).toBe(true);

    const stubPath = path.join(
      tmpDir,
      ".elm-pages-db",
      "Db",
      "Migrate",
      "V2.elm"
    );
    expect(fs.existsSync(stubPath)).toBe(true);

    const chainPath = path.join(tmpDir, ".elm-pages-db", "MigrateChain.elm");
    expect(fs.existsSync(chainPath)).toBe(true);

    // Verify schema version bumped
    const schemaVersion = await readSchemaVersion(tmpDir);
    expect(schemaVersion).toBe(2);

    // === Step 3: Detection shows migration needed (before implementing) ===
    const detectionBefore = await detectMigrationNeeded(tmpDir);
    expect(detectionBefore.action).toBe("migrate");
    expect(detectionBefore.fromVersion).toBe(1);
    expect(detectionBefore.toVersion).toBe(2);

    // === Step 4: Validation fails because stub has sentinel ===
    const validationBefore = await validateMigrationChain(tmpDir, 1, 2);
    expect(validationBefore.valid).toBe(false);
    expect(validationBefore.unimplemented).toContain("Db/Migrate/V2.elm");

    // === Step 5: User implements the migration stub ===
    const implementedMigration = `module Db.Migrate.V2 exposing (db)

import Db
import Db.V1


db : Db.V1.Db -> Db.Db
db old =
    { counter = old.counter
    , name = ""
    }
`;
    fs.writeFileSync(stubPath, implementedMigration);

    // === Step 6: Validation now passes ===
    const validationAfter = await validateMigrationChain(tmpDir, 1, 2);
    expect(validationAfter.valid).toBe(true);

    // === Step 7: Simulate migration execution via render.js handler pattern ===
    // db-migrate-read: read old db.bin
    const dbBinContents = fs.readFileSync(path.join(tmpDir, "db.bin"));
    const parsed = parseDbBinHeader(dbBinContents);
    const migrateReadResponse = {
      version: parsed.schemaVersion,
      data: Buffer.from(parsed.wire3Data).toString("base64"),
    };
    expect(migrateReadResponse.version).toBe(1);

    // Verify base64 round-trip of wire3 data
    const decodedWire3 = Buffer.from(migrateReadResponse.data, "base64");
    expect([...decodedWire3]).toEqual([0x01, 0x02, 0x03, 0x04]);

    // === Step 8: Simulate migration write (db-migrate-write handler pattern) ===
    // After Elm migration chain runs, it would encode new data and call db-migrate-write
    const migratedWire3 = Buffer.from([0x0A, 0x0B, 0x0C, 0x0D, 0x0E]);

    // Update Db.elm to V2 schema (user already did this before migrate)
    fs.writeFileSync(
      path.join(tmpDir, "script/src/Db.elm"),
      dbSourceV2
    );
    const hashV2 = await computeSchemaHash(
      path.join(tmpDir, "script/src/Db.elm")
    );

    // Write new db.bin (simulating handler)
    const dbBinPath = path.join(tmpDir, "db.bin");

    // Create backup
    fs.copyFileSync(dbBinPath, `${dbBinPath}.backup`);

    // Write with new schema version and hash
    const newDbBin = buildDbBin(hashV2, schemaVersion, migratedWire3);
    const tmpPath = `${dbBinPath}.tmp.${process.pid}`;
    fs.writeFileSync(tmpPath, newDbBin);
    fs.renameSync(tmpPath, dbBinPath);

    // === Step 9: Verify final state ===
    const finalDbBin = parseDbBinHeader(
      fs.readFileSync(path.join(tmpDir, "db.bin"))
    );
    expect(finalDbBin.schemaVersion).toBe(2);
    expect(finalDbBin.schemaHashHex).toBe(hashV2);
    expect([...finalDbBin.wire3Data]).toEqual([0x0A, 0x0B, 0x0C, 0x0D, 0x0E]);

    // Verify backup preserved original data
    const backupDbBin = parseDbBinHeader(
      fs.readFileSync(`${dbBinPath}.backup`)
    );
    expect(backupDbBin.schemaVersion).toBe(1);
    expect([...backupDbBin.wire3Data]).toEqual([0x01, 0x02, 0x03, 0x04]);

    // Verify migration is no longer needed
    // Update schema version to match db.bin (handler does this)
    const finalDetection = await detectMigrationNeeded(tmpDir);
    expect(finalDetection.action).toBe("up-to-date");
  });
});

describe("E2E: multi-step migration (V1 → V2 → V3)", () => {
  it("full flow: two migrations applied in chain", async () => {
    // === Step 1: Set up project at V1 with seeded db.bin ===
    setupProject(dbSourceV1);
    const hashV1 = await computeSchemaHash(
      path.join(tmpDir, "script/src/Db.elm")
    );
    seedDbBin(hashV1, 1, Buffer.from([0xAA, 0xBB]));
    await writeSchemaVersion(tmpDir, 1);

    // === Step 2: First migration (V1 → V2) ===
    await migrate();

    expect(await readSchemaVersion(tmpDir)).toBe(2);
    expect(
      fs.existsSync(path.join(tmpDir, ".elm-pages-db", "Db", "V1.elm"))
    ).toBe(true);
    expect(
      fs.existsSync(
        path.join(tmpDir, ".elm-pages-db", "Db", "Migrate", "V2.elm")
      )
    ).toBe(true);

    // Implement V2 migration
    fs.writeFileSync(
      path.join(tmpDir, ".elm-pages-db", "Db", "Migrate", "V2.elm"),
      `module Db.Migrate.V2 exposing (db)

import Db
import Db.V1


db : Db.V1.Db -> Db.Db
db old =
    { counter = old.counter
    , name = "migrated"
    }
`
    );

    // Simulate migration execution: update db.bin to V2
    fs.writeFileSync(
      path.join(tmpDir, "script/src/Db.elm"),
      dbSourceV2
    );
    const hashV2 = await computeSchemaHash(
      path.join(tmpDir, "script/src/Db.elm")
    );
    const migratedV2Wire3 = Buffer.from([0xCC, 0xDD, 0xEE]);
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(hashV2, 2, migratedV2Wire3)
    );

    // Verify V2 state
    const v2Detection = await detectMigrationNeeded(tmpDir);
    expect(v2Detection.action).toBe("up-to-date");

    // === Step 3: Second migration (V2 → V3) ===
    await migrate();

    expect(await readSchemaVersion(tmpDir)).toBe(3);
    expect(
      fs.existsSync(path.join(tmpDir, ".elm-pages-db", "Db", "V2.elm"))
    ).toBe(true);
    expect(
      fs.existsSync(
        path.join(tmpDir, ".elm-pages-db", "Db", "Migrate", "V3.elm")
      )
    ).toBe(true);

    // V1 snapshot should still exist
    expect(
      fs.existsSync(path.join(tmpDir, ".elm-pages-db", "Db", "V1.elm"))
    ).toBe(true);

    // === Step 4: Implement V3 migration ===
    fs.writeFileSync(
      path.join(tmpDir, ".elm-pages-db", "Db", "Migrate", "V3.elm"),
      `module Db.Migrate.V3 exposing (db)

import Db
import Db.V2


db : Db.V2.Db -> Db.Db
db old =
    { counter = old.counter
    , name = old.name
    , active = True
    }
`
    );

    // === Step 5: Validate full chain ===
    const validation = await validateMigrationChain(tmpDir, 2, 3);
    expect(validation.valid).toBe(true);

    // Also validate from V1 (for a db.bin that's at V1)
    const fullValidation = await validateMigrationChain(tmpDir, 1, 3);
    expect(fullValidation.valid).toBe(true);
  });
});

describe("E2E: migration from stale db.bin (V1 data, schema at V3)", () => {
  it("detects need to migrate from V1 all the way to V3", async () => {
    setupProject(dbSourceV3);
    const hashV1 = crypto.createHash("sha256").update("v1-schema").digest("hex");
    seedDbBin(hashV1, 1, Buffer.from([0x11, 0x22]));
    await writeSchemaVersion(tmpDir, 3);

    // Set up complete chain V1 → V2 → V3
    const dbDir = path.join(tmpDir, ".elm-pages-db", "Db");
    const migrateDir = path.join(dbDir, "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });

    fs.writeFileSync(
      path.join(dbDir, "V1.elm"),
      `module Db.V1 exposing (Db, init)

type alias Db =
    { counter : Int
    }

init : Db
init =
    { counter = 0
    }
`
    );

    fs.writeFileSync(
      path.join(dbDir, "V2.elm"),
      `module Db.V2 exposing (Db, init)

type alias Db =
    { counter : Int
    , name : String
    }

init : Db
init =
    { counter = 0
    , name = ""
    }
`
    );

    fs.writeFileSync(
      path.join(migrateDir, "V2.elm"),
      `module Db.Migrate.V2 exposing (db)

import Db.V1
import Db.V2


db : Db.V1.Db -> Db.V2.Db
db old =
    { counter = old.counter
    , name = ""
    }
`
    );

    fs.writeFileSync(
      path.join(migrateDir, "V3.elm"),
      `module Db.Migrate.V3 exposing (db)

import Db
import Db.V2


db : Db.V2.Db -> Db.Db
db old =
    { counter = old.counter
    , name = old.name
    , active = True
    }
`
    );

    // Generate chain
    await writeMigrateChain(tmpDir, 3);

    // Detection
    const detection = await detectMigrationNeeded(tmpDir);
    expect(detection.action).toBe("migrate");
    expect(detection.fromVersion).toBe(1);
    expect(detection.toVersion).toBe(3);

    // Validation
    const validation = await validateMigrationChain(tmpDir, 1, 3);
    expect(validation.valid).toBe(true);

    // Simulate the migration execution: read V1, chain through, write V3
    const oldDbBin = parseDbBinHeader(
      fs.readFileSync(path.join(tmpDir, "db.bin"))
    );
    expect(oldDbBin.schemaVersion).toBe(1);

    // After migration chain runs, write new db.bin at V3
    const hashV3 = await computeSchemaHash(
      path.join(tmpDir, "script/src/Db.elm")
    );
    const migratedWire3 = Buffer.from([0x33, 0x44, 0x55, 0x66]);
    fs.writeFileSync(
      path.join(tmpDir, "db.bin"),
      buildDbBin(hashV3, 3, migratedWire3)
    );

    // Verify final state
    const finalDetection = await detectMigrationNeeded(tmpDir);
    expect(finalDetection.action).toBe("up-to-date");

    const finalDbBin = parseDbBinHeader(
      fs.readFileSync(path.join(tmpDir, "db.bin"))
    );
    expect(finalDbBin.schemaVersion).toBe(3);
    expect([...finalDbBin.wire3Data]).toEqual([0x33, 0x44, 0x55, 0x66]);
  });
});

describe("E2E: error cases", () => {
  it("migrate prints guidance when migration is already pending", async () => {
    setupProject(dbSourceV1);
    const hashV1 = crypto.createHash("sha256").update("v1").digest("hex");
    seedDbBin(hashV1, 1, Buffer.from([1, 2, 3]));
    // Schema already at V2 but db.bin still at V1
    await writeSchemaVersion(tmpDir, 2);

    const logSpy = vi.spyOn(console, "log");
    await migrate();

    const logOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(logOutput).toContain("Pending migration");
    logSpy.mockRestore();
  });

  it("validation fails when snapshot is missing", async () => {
    setupProject(dbSourceV2);
    const hashV1 = crypto.createHash("sha256").update("v1").digest("hex");
    seedDbBin(hashV1, 1, Buffer.from([1, 2, 3]));
    await writeSchemaVersion(tmpDir, 2);

    // Create migration stub but NOT the snapshot
    const migrateDir = path.join(
      tmpDir,
      ".elm-pages-db",
      "Db",
      "Migrate"
    );
    fs.mkdirSync(migrateDir, { recursive: true });
    fs.writeFileSync(
      path.join(migrateDir, "V2.elm"),
      `module Db.Migrate.V2 exposing (db)
import Db
import Db.V1
db old = { counter = old.counter, name = "" }
`
    );

    const validation = await validateMigrationChain(tmpDir, 1, 2);
    expect(validation.valid).toBe(false);
    expect(validation.missingFiles).toContain("Db/V1.elm");
  });

  it("validation fails when migration stub is unimplemented", async () => {
    setupProject(dbSourceV2);
    const hashV1 = crypto.createHash("sha256").update("v1").digest("hex");
    seedDbBin(hashV1, 1, Buffer.from([1, 2, 3]));
    await writeSchemaVersion(tmpDir, 2);

    const dbDir = path.join(tmpDir, ".elm-pages-db", "Db");
    const migrateDir = path.join(dbDir, "Migrate");
    fs.mkdirSync(migrateDir, { recursive: true });

    fs.writeFileSync(
      path.join(dbDir, "V1.elm"),
      "module Db.V1 exposing (Db)\ntype alias Db = { counter : Int }\n"
    );
    fs.writeFileSync(
      path.join(migrateDir, "V2.elm"),
      `module Db.Migrate.V2 exposing (db)

import Db
import Db.V1


db : Db.V1.Db -> Db.Db
db old =
    todo_implement_migration_V1_to_V2
`
    );

    const validation = await validateMigrationChain(tmpDir, 1, 2);
    expect(validation.valid).toBe(false);
    expect(validation.unimplemented).toContain("Db/Migrate/V2.elm");
  });

  it("detectMigrationNeeded returns error when db.bin version > schema version", async () => {
    setupProject(dbSourceV1);
    const hash = crypto.createHash("sha256").update("future").digest("hex");
    seedDbBin(hash, 5, Buffer.from([1, 2, 3]));
    await writeSchemaVersion(tmpDir, 2);

    const detection = await detectMigrationNeeded(tmpDir);
    expect(detection.action).toBe("error");
  });

  it("detectMigrationNeeded returns no-db when db.bin does not exist", async () => {
    setupProject(dbSourceV1);
    await writeSchemaVersion(tmpDir, 1);
    // No db.bin created

    const detection = await detectMigrationNeeded(tmpDir);
    expect(detection.action).toBe("no-db");
  });
});

describe("E2E: path consistency", () => {
  it("CLI migrate and detectMigrationNeeded use same paths (CWD)", async () => {
    // This test verifies that the path mismatch bug is fixed:
    // - CLI commands use process.cwd() for db.bin and .elm-pages-db
    // - detectMigrationNeeded should also use the same directory
    // - db.bin should be at CWD, not at projectDirectory

    setupProject(dbSourceV1);
    const hashV1 = await computeSchemaHash(
      path.join(tmpDir, "script/src/Db.elm")
    );
    seedDbBin(hashV1, 1, Buffer.from([0xFF]));
    await writeSchemaVersion(tmpDir, 1);

    // Verify db.bin is at CWD (tmpDir), NOT at script/
    expect(fs.existsSync(path.join(tmpDir, "db.bin"))).toBe(true);
    expect(fs.existsSync(path.join(tmpDir, "script", "db.bin"))).toBe(false);

    // Run migrate (uses CWD)
    await migrate();

    // Verify .elm-pages-db is at CWD (tmpDir), NOT at script/
    expect(
      fs.existsSync(
        path.join(tmpDir, ".elm-pages-db", "schema-version.json")
      )
    ).toBe(true);
    expect(
      fs.existsSync(
        path.join(tmpDir, "script", ".elm-pages-db", "schema-version.json")
      )
    ).toBe(false);

    // detectMigrationNeeded should find db.bin at CWD
    const detection = await detectMigrationNeeded(tmpDir);
    expect(detection.action).toBe("migrate");
    expect(detection.fromVersion).toBe(1);
    expect(detection.toVersion).toBe(2);
  });

  it("render.js handler pattern uses same db.bin location as CLI", async () => {
    // Simulate what render.js does: path.resolve(...[]) = process.cwd()
    const runtimeDir = path.resolve(...[]);
    expect(runtimeDir).toBe(process.cwd());
    // Use realpath to handle macOS /var -> /private/var symlink
    expect(fs.realpathSync(runtimeDir)).toBe(fs.realpathSync(tmpDir));

    // db.bin at CWD
    setupProject(dbSourceV1);
    const hashV1 = await computeSchemaHash(
      path.join(tmpDir, "script/src/Db.elm")
    );
    seedDbBin(hashV1, 1, Buffer.from([0xDE, 0xAD]));

    // Simulate handler reading db.bin from resolved CWD
    const dbBinPath = path.resolve(runtimeDir, "db.bin");
    expect(fs.existsSync(dbBinPath)).toBe(true);
    const parsed = parseDbBinHeader(fs.readFileSync(dbBinPath));
    expect(parsed.schemaVersion).toBe(1);
    expect([...parsed.wire3Data]).toEqual([0xDE, 0xAD]);
  });
});

describe("E2E: prepareMigrationSourceDirs with project structure", () => {
  it("adds .elm-pages-db from CWD to compile dir source-directories", async () => {
    setupProject(dbSourceV1);

    // Set up a compile dir with elm.json (simulating elm-stuff/elm-pages)
    const compileDir = path.join(tmpDir, "script", "elm-stuff", "elm-pages");
    fs.mkdirSync(compileDir, { recursive: true });
    fs.writeFileSync(
      path.join(compileDir, "elm.json"),
      JSON.stringify({
        type: "application",
        "source-directories": ["src", ".elm-pages"],
      })
    );

    // Create .elm-pages-db at CWD (not at projectDirectory)
    await writeSchemaVersion(tmpDir, 1);
    await migrate();

    // prepareMigrationSourceDirs should resolve .elm-pages-db relative to compileDir
    const restore = await prepareMigrationSourceDirs(compileDir, tmpDir);

    const elmJson = JSON.parse(
      fs.readFileSync(path.join(compileDir, "elm.json"), "utf8")
    );
    const sourceDirs = elmJson["source-directories"];
    expect(sourceDirs.length).toBe(3);
    expect(sourceDirs.some((d) => d.includes(".elm-pages-db"))).toBe(true);

    // The .elm-pages-db path should be resolvable from compileDir
    const migrationDirRelative = sourceDirs.find((d) =>
      d.includes(".elm-pages-db")
    );
    const migrationDirAbsolute = path.resolve(compileDir, migrationDirRelative);
    expect(fs.existsSync(migrationDirAbsolute)).toBe(true);
    expect(
      fs.existsSync(path.join(migrationDirAbsolute, "Db", "V1.elm"))
    ).toBe(true);

    // Restore removes it
    await restore();
    const restored = JSON.parse(
      fs.readFileSync(path.join(compileDir, "elm.json"), "utf8")
    );
    expect(restored["source-directories"]).toEqual(["src", ".elm-pages"]);
  });
});

describe("E2E: db-migrate-read and db-migrate-write handler simulation", () => {
  it("read handler returns version and base64 data from db.bin", async () => {
    setupProject(dbSourceV1);
    const hashV1 = crypto.createHash("sha256").update("v1").digest("hex");
    const wire3Data = Buffer.from([0x10, 0x20, 0x30, 0x40, 0x50]);
    seedDbBin(hashV1, 2, wire3Data);

    // Simulate runDbMigrateRead handler
    const dbBinPath = path.resolve(tmpDir, "db.bin");
    const fileContents = fs.readFileSync(dbBinPath);
    const parsed = parseDbBinHeader(fileContents);

    const response = {
      version: parsed.schemaVersion,
      data: Buffer.from(parsed.wire3Data).toString("base64"),
    };

    expect(response.version).toBe(2);
    const decoded = Buffer.from(response.data, "base64");
    expect([...decoded]).toEqual([0x10, 0x20, 0x30, 0x40, 0x50]);
  });

  it("read handler returns {version: 0, data: ''} when no db.bin", () => {
    // Simulate no db.bin case
    const dbBinPath = path.resolve(tmpDir, "db.bin");
    let response;
    try {
      fs.readFileSync(dbBinPath);
    } catch (error) {
      if (error.code === "ENOENT") {
        response = { version: 0, data: "" };
      }
    }
    expect(response).toEqual({ version: 0, data: "" });
  });

  it("write handler creates db.bin with backup", async () => {
    setupProject(dbSourceV2);
    const hashV1 = crypto.createHash("sha256").update("v1").digest("hex");
    seedDbBin(hashV1, 1, Buffer.from([0x01, 0x02]));

    const dbBinPath = path.resolve(tmpDir, "db.bin");

    // Simulate runDbMigrateWrite handler
    const newWire3 = Buffer.from([0xAA, 0xBB, 0xCC]);
    const base64Data = newWire3.toString("base64");

    // Read schema info
    const newSchemaVersion = 2;
    const hashV2 = await computeSchemaHash(
      path.join(tmpDir, "script/src/Db.elm")
    );

    // Create backup
    fs.copyFileSync(dbBinPath, `${dbBinPath}.backup`);

    // Build and write
    const decodedData = Buffer.from(base64Data, "base64");
    const fileBuffer = buildDbBin(hashV2, newSchemaVersion, decodedData);
    const tmpPath = `${dbBinPath}.tmp.${process.pid}`;
    fs.writeFileSync(tmpPath, fileBuffer);
    fs.renameSync(tmpPath, dbBinPath);

    // Verify new db.bin
    const newParsed = parseDbBinHeader(fs.readFileSync(dbBinPath));
    expect(newParsed.schemaVersion).toBe(2);
    expect(newParsed.schemaHashHex).toBe(hashV2);
    expect([...newParsed.wire3Data]).toEqual([0xAA, 0xBB, 0xCC]);

    // Verify backup preserved
    const backupParsed = parseDbBinHeader(
      fs.readFileSync(`${dbBinPath}.backup`)
    );
    expect(backupParsed.schemaVersion).toBe(1);
    expect([...backupParsed.wire3Data]).toEqual([0x01, 0x02]);
  });
});

