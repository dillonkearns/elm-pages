import { describe, it, expect } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { computeSchemaHash, hashToBytes, bytesToHash } from "../src/db-schema.js";

describe("db-schema", () => {
  describe("computeSchemaHash", () => {
    it("returns a 64-character hex string", async () => {
      const tmpDir = await fs.promises.mkdtemp(
        path.join(os.tmpdir(), "db-schema-test-")
      );
      const dbElmPath = path.join(tmpDir, "Db.elm");
      await fs.promises.writeFile(
        dbElmPath,
        `module Db exposing (Db, init)

type alias Db = { counter : Int }

init : Db
init = { counter = 0 }
`
      );

      const hash = await computeSchemaHash(dbElmPath);

      expect(hash).toMatch(/^[0-9a-f]{64}$/);

      await fs.promises.rm(tmpDir, { recursive: true });
    });

    it("returns the same hash for the same content", async () => {
      const tmpDir = await fs.promises.mkdtemp(
        path.join(os.tmpdir(), "db-schema-test-")
      );
      const content = `module Db exposing (Db, init)\ntype alias Db = { x : Int }\ninit = { x = 0 }\n`;
      const path1 = path.join(tmpDir, "Db1.elm");
      const path2 = path.join(tmpDir, "Db2.elm");
      await fs.promises.writeFile(path1, content);
      await fs.promises.writeFile(path2, content);

      const hash1 = await computeSchemaHash(path1);
      const hash2 = await computeSchemaHash(path2);

      expect(hash1).toBe(hash2);

      await fs.promises.rm(tmpDir, { recursive: true });
    });

    it("returns different hashes for different content", async () => {
      const tmpDir = await fs.promises.mkdtemp(
        path.join(os.tmpdir(), "db-schema-test-")
      );
      const path1 = path.join(tmpDir, "Db1.elm");
      const path2 = path.join(tmpDir, "Db2.elm");
      await fs.promises.writeFile(path1, "module Db exposing (Db)\ntype alias Db = { x : Int }\n");
      await fs.promises.writeFile(path2, "module Db exposing (Db)\ntype alias Db = { y : String }\n");

      const hash1 = await computeSchemaHash(path1);
      const hash2 = await computeSchemaHash(path2);

      expect(hash1).not.toBe(hash2);

      await fs.promises.rm(tmpDir, { recursive: true });
    });
  });

  describe("hashToBytes / bytesToHash", () => {
    it("round-trips a hex hash string", () => {
      const hex = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2";
      const bytes = hashToBytes(hex);
      expect(bytes).toBeInstanceOf(Buffer);
      expect(bytes.length).toBe(32);
      expect(bytesToHash(bytes)).toBe(hex);
    });

    it("produces 32 bytes from a SHA-256 hex string", () => {
      const hex = "0".repeat(64);
      const bytes = hashToBytes(hex);
      expect(bytes.length).toBe(32);
      expect([...bytes]).toEqual(new Array(32).fill(0));
    });
  });
});
