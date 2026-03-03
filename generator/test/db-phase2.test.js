/**
 * Tests for Phase 2 features: schema versioning, deep compare, db status.
 */

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as crypto from "node:crypto";
import {
  computeSchemaHash,
  loadSchemaMeta,
  saveSchemaMeta,
  readSchemaVersion,
} from "../src/db-schema.js";
import {
  parseDbBinHeader,
  buildDbBin,
  DB_FORMAT_VERSION,
  DB_HEADER_SIZE,
  DB_MAGIC,
} from "../src/db-bin-format.js";

let tmpDir;

beforeEach(async () => {
  tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "db-phase2-test-"));
});

afterEach(async () => {
  await fs.promises.rm(tmpDir, { recursive: true });
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

// --- Schema version tracking ---

describe("schema version tracking", () => {
  it("returns 1 when no migration files exist", async () => {
    const version = await readSchemaVersion(tmpDir);
    expect(version).toBe(1);
  });

  it("reads schema version from highest V*.elm file", async () => {
    setupSchemaVersion(tmpDir, 3);
    const version = await readSchemaVersion(tmpDir);
    expect(version).toBe(3);
  });
});

// --- Schema meta cache ---

describe("schema meta cache", () => {
  it("returns null when no meta file exists", async () => {
    const meta = await loadSchemaMeta(tmpDir);
    expect(meta).toBeNull();
  });

  it("writes and reads schema meta", async () => {
    await saveSchemaMeta(tmpDir, "abc123", "def456");
    const meta = await loadSchemaMeta(tmpDir);
    expect(meta.sourceHash).toBe("abc123");
    expect(meta.compiledHash).toBe("def456");
  });

  it("creates .elm-pages directory if needed", async () => {
    await saveSchemaMeta(tmpDir, "hash1", "hash2");
    const dirExists = fs.existsSync(path.join(tmpDir, ".elm-pages"));
    expect(dirExists).toBe(true);
  });

  it("overwrites existing meta", async () => {
    await saveSchemaMeta(tmpDir, "old", "old");
    await saveSchemaMeta(tmpDir, "new", "new");
    const meta = await loadSchemaMeta(tmpDir);
    expect(meta.sourceHash).toBe("new");
    expect(meta.compiledHash).toBe("new");
  });
});

// --- Schema hash computation ---

describe("schema hash computation", () => {
  it("produces different hashes for different source", async () => {
    const file1 = path.join(tmpDir, "Db1.elm");
    const file2 = path.join(tmpDir, "Db2.elm");
    await fs.promises.writeFile(file1, "module Db exposing (Db)\ntype alias Db = { a : Int }");
    await fs.promises.writeFile(file2, "module Db exposing (Db)\ntype alias Db = { b : Int }");

    const hash1 = await computeSchemaHash(file1);
    const hash2 = await computeSchemaHash(file2);
    expect(hash1).not.toBe(hash2);
  });

  it("produces same hash for identical source", async () => {
    const file1 = path.join(tmpDir, "Db1.elm");
    const file2 = path.join(tmpDir, "Db2.elm");
    const source = "module Db exposing (Db)\ntype alias Db = { a : Int }";
    await fs.promises.writeFile(file1, source);
    await fs.promises.writeFile(file2, source);

    const hash1 = await computeSchemaHash(file1);
    const hash2 = await computeSchemaHash(file2);
    expect(hash1).toBe(hash2);
  });

  it("detects whitespace-only changes", async () => {
    const file1 = path.join(tmpDir, "Db1.elm");
    const file2 = path.join(tmpDir, "Db2.elm");
    await fs.promises.writeFile(file1, "module Db exposing (Db)\ntype alias Db = { a : Int }");
    await fs.promises.writeFile(file2, "module Db exposing (Db)\n\ntype alias Db = { a : Int }");

    const hash1 = await computeSchemaHash(file1);
    const hash2 = await computeSchemaHash(file2);
    // Source text hash will differ — deep compare would resolve this
    expect(hash1).not.toBe(hash2);
  });
});

// --- db.bin format versioning ---

describe("db.bin format versioning", () => {
  const testHash = crypto.createHash("sha256").update("test").digest("hex");

  it("includes format version and schema version", () => {
    const buf = buildDbBin(testHash, 3, Buffer.from([1, 2]));
    const parsed = parseDbBinHeader(buf);

    expect(parsed.formatVersion).toBe(1);
    expect(parsed.schemaVersion).toBe(3);
  });

  it("schema version is preserved on re-write", () => {
    const buf = buildDbBin(testHash, 7, Buffer.from([1]));
    const parsed = parseDbBinHeader(buf);

    const newHash = crypto.createHash("sha256").update("new").digest("hex");
    const newBuf = buildDbBin(newHash, parsed.schemaVersion, parsed.wire3Data);
    const reparsed = parseDbBinHeader(newBuf);

    expect(reparsed.schemaVersion).toBe(7);
    expect(reparsed.schemaHashHex).toBe(newHash);
  });
});

// --- db status command ---

describe("db status command", () => {
  it("readSchemaVersion + parseDbBinHeader give consistent version info", async () => {
    setupSchemaVersion(tmpDir, 3);
    const version = await readSchemaVersion(tmpDir);

    const testHash = crypto.createHash("sha256").update("x").digest("hex");
    const buf = buildDbBin(testHash, version, Buffer.alloc(0));
    const parsed = parseDbBinHeader(buf);

    expect(parsed.schemaVersion).toBe(version);
    expect(parsed.schemaVersion).toBe(3);
  });

  it("detects version mismatch between migration files and db.bin", async () => {
    setupSchemaVersion(tmpDir, 5);
    const currentVersion = await readSchemaVersion(tmpDir);

    const testHash = crypto.createHash("sha256").update("x").digest("hex");
    const buf = buildDbBin(testHash, 3, Buffer.alloc(0));
    const parsed = parseDbBinHeader(buf);

    expect(parsed.schemaVersion).not.toBe(currentVersion);
    expect(parsed.schemaVersion).toBe(3);
    expect(currentVersion).toBe(5);
  });
});
