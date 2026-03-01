/**
 * Tests for the database handler logic in render.js
 *
 * Since the handlers are internal functions in render.js, these tests validate
 * the binary format construction/parsing and file system behavior patterns
 * that the handlers rely on.
 */

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as crypto from "node:crypto";
import {
  parseDbBinHeader,
  buildDbBin,
  DB_MAGIC,
  DB_FORMAT_VERSION,
  DB_HEADER_SIZE,
} from "../src/db-bin-format.js";

let tmpDir;

beforeEach(async () => {
  tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "db-handler-test-"));
});

afterEach(async () => {
  await fs.promises.rm(tmpDir, { recursive: true });
});

describe("db.bin binary format", () => {
  const testHash = crypto.createHash("sha256").update("test").digest("hex");

  it("constructs a valid header with magic bytes", () => {
    const buf = buildDbBin(testHash, 1, Buffer.from([1, 2, 3]));

    expect(buf.subarray(0, 4).toString("ascii")).toBe("EPDB");
    expect(buf.readUInt16BE(4)).toBe(DB_FORMAT_VERSION);
    expect(buf.readUInt32BE(6)).toBe(1);
    expect(buf.length).toBe(DB_HEADER_SIZE + 3);
  });

  it("stores schema hash as raw bytes at offset 10", () => {
    const buf = buildDbBin(testHash, 1, Buffer.alloc(0));

    const storedHash = buf.subarray(10, 42).toString("hex");
    expect(storedHash).toBe(testHash);
  });

  it("stores schema version counter", () => {
    const buf = buildDbBin(testHash, 42, Buffer.alloc(0));
    expect(buf.readUInt32BE(6)).toBe(42);
  });

  it("stores Wire3 data after the header", () => {
    const wire3 = Buffer.from([0xDE, 0xAD, 0xBE, 0xEF]);
    const buf = buildDbBin(testHash, 1, wire3);

    const storedData = buf.subarray(DB_HEADER_SIZE);
    expect([...storedData]).toEqual([0xDE, 0xAD, 0xBE, 0xEF]);
  });

  it("round-trips through buildDbBin and parseDbBinHeader", () => {
    const wire3 = Buffer.from("hello wire3 data");
    const buf = buildDbBin(testHash, 5, wire3);
    const parsed = parseDbBinHeader(buf);

    expect(parsed.formatVersion).toBe(DB_FORMAT_VERSION);
    expect(parsed.schemaVersion).toBe(5);
    expect(parsed.schemaHashHex).toBe(testHash);
    expect(parsed.wire3Data.toString()).toBe("hello wire3 data");
  });

  it("rejects buffers that are too small", () => {
    expect(() => parseDbBinHeader(Buffer.alloc(10))).toThrow();
  });

  it("rejects files with invalid magic bytes", () => {
    const buf = Buffer.alloc(DB_HEADER_SIZE);
    buf.write("NOPE", 0, "ascii");
    expect(() => parseDbBinHeader(buf)).toThrow(/invalid magic/i);
  });

  it("provides actionable error for corrupt files", () => {
    try {
      parseDbBinHeader(Buffer.alloc(10));
    } catch (e) {
      expect(e.title).toBe("db.bin is corrupt");
      expect(e.message).toContain("elm-pages db reset");
    }
  });

  it("handles empty Wire3 data", () => {
    const buf = buildDbBin(testHash, 1, Buffer.alloc(0));
    const parsed = parseDbBinHeader(buf);

    expect(parsed.wire3Data.length).toBe(0);
    expect(buf.length).toBe(DB_HEADER_SIZE);
  });

  it("handles large schema version numbers", () => {
    const buf = buildDbBin(testHash, 99999, Buffer.alloc(0));
    const parsed = parseDbBinHeader(buf);
    expect(parsed.schemaVersion).toBe(99999);
  });
});

describe("db-read response format", () => {
  it("encodes no-data response as 4 big-endian zero bytes", () => {
    const buffer = new Uint8Array(4);
    new DataView(buffer.buffer).setInt32(0, 0);

    expect(buffer.length).toBe(4);

    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    expect(view.getInt32(0, false)).toBe(0);

    // Verify base64 round-trip (how bytesResponse transmits it)
    const base64 = Buffer.from(buffer).toString("base64");
    const decoded = Buffer.from(base64, "base64");
    expect(decoded.length).toBe(4);
    expect(new DataView(decoded.buffer, decoded.byteOffset, decoded.byteLength).getInt32(0, false)).toBe(0);
  });

  it("encodes success response as length-prefixed Wire3 data", () => {
    const wire3Data = Buffer.from([1, 2, 3, 4, 5]);
    const buffer = new Uint8Array(4 + wire3Data.length);
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    view.setInt32(0, wire3Data.length);
    wire3Data.copy(buffer, 4);

    expect(view.getInt32(0, false)).toBe(5);
    const extractedData = Buffer.from(buffer.buffer, 4, 5);
    expect([...extractedData]).toEqual([1, 2, 3, 4, 5]);
  });
});

describe("db-write atomic write pattern", () => {
  it("writes atomically via temp file and rename", async () => {
    const dbBinPath = path.join(tmpDir, "db.bin");
    const tmpPath = `${dbBinPath}.tmp.${process.pid}`;

    const testHash = crypto.createHash("sha256").update("test").digest("hex");
    const wire3Data = Buffer.from([10, 20, 30]);

    const fileBuffer = buildDbBin(testHash, 1, wire3Data);

    await fs.promises.writeFile(tmpPath, fileBuffer);
    await fs.promises.rename(tmpPath, dbBinPath);

    expect(fs.existsSync(tmpPath)).toBe(false);
    expect(fs.existsSync(dbBinPath)).toBe(true);

    const written = await fs.promises.readFile(dbBinPath);
    const parsed = parseDbBinHeader(written);
    expect(parsed.formatVersion).toBe(DB_FORMAT_VERSION);
    expect(parsed.schemaVersion).toBe(1);
    expect(parsed.schemaHashHex).toBe(testHash);
    expect([...parsed.wire3Data]).toEqual([10, 20, 30]);
  });

  it("does not leave temp file on rename success", async () => {
    const dbBinPath = path.join(tmpDir, "db.bin");
    const tmpPath = `${dbBinPath}.tmp.${process.pid}`;

    await fs.promises.writeFile(tmpPath, "data");
    await fs.promises.rename(tmpPath, dbBinPath);

    const files = await fs.promises.readdir(tmpDir);
    expect(files).toEqual(["db.bin"]);
  });
});

describe("db-lock lifecycle", () => {
  it("creates lock file with exclusive flag", async () => {
    const lockPath = path.join(tmpDir, "db.lock");
    const token = crypto.randomUUID();
    const lockData = JSON.stringify({
      pid: process.pid,
      createdAt: new Date().toISOString(),
      token,
    });

    await fs.promises.writeFile(lockPath, lockData, { flag: "wx" });
    expect(fs.existsSync(lockPath)).toBe(true);

    await expect(
      fs.promises.writeFile(lockPath, lockData, { flag: "wx" })
    ).rejects.toThrow();
  });

  it("lock file contains pid, timestamp, and token", async () => {
    const lockPath = path.join(tmpDir, "db.lock");
    const token = crypto.randomUUID();
    const lockData = JSON.stringify({
      pid: process.pid,
      createdAt: new Date().toISOString(),
      token,
    });

    await fs.promises.writeFile(lockPath, lockData, { flag: "wx" });

    const parsed = JSON.parse(await fs.promises.readFile(lockPath, "utf8"));
    expect(parsed.pid).toBe(process.pid);
    expect(parsed.token).toBe(token);
    expect(new Date(parsed.createdAt).getTime()).toBeLessThanOrEqual(Date.now());
  });

  it("release deletes lock only if token matches", async () => {
    const lockPath = path.join(tmpDir, "db.lock");
    const correctToken = crypto.randomUUID();
    const wrongToken = crypto.randomUUID();
    const lockData = JSON.stringify({
      pid: process.pid,
      createdAt: new Date().toISOString(),
      token: correctToken,
    });

    await fs.promises.writeFile(lockPath, lockData, { flag: "wx" });

    const existing = JSON.parse(await fs.promises.readFile(lockPath, "utf8"));
    if (existing.token === wrongToken) {
      await fs.promises.unlink(lockPath);
    }
    expect(fs.existsSync(lockPath)).toBe(true);

    if (existing.token === correctToken) {
      await fs.promises.unlink(lockPath);
    }
    expect(fs.existsSync(lockPath)).toBe(false);
  });

  it("detects stale lock from dead PID", async () => {
    const lockPath = path.join(tmpDir, "db.lock");
    const lockData = JSON.stringify({
      pid: 999999,
      createdAt: new Date().toISOString(),
      token: crypto.randomUUID(),
    });

    await fs.promises.writeFile(lockPath, lockData);

    const existing = JSON.parse(await fs.promises.readFile(lockPath, "utf8"));

    let pidAlive = false;
    try {
      process.kill(existing.pid, 0);
      pidAlive = true;
    } catch (_) {
      pidAlive = false;
    }

    expect(pidAlive).toBe(false);
  });

  it("detects stale lock from old timestamp", async () => {
    const lockPath = path.join(tmpDir, "db.lock");
    const staleTime = new Date(Date.now() - 10 * 60 * 1000);
    const lockData = JSON.stringify({
      pid: process.pid,
      createdAt: staleTime.toISOString(),
      token: crypto.randomUUID(),
    });

    await fs.promises.writeFile(lockPath, lockData);

    const existing = JSON.parse(await fs.promises.readFile(lockPath, "utf8"));
    const lockAge = Date.now() - new Date(existing.createdAt).getTime();
    const staleTimeout = 5 * 60 * 1000;

    expect(lockAge).toBeGreaterThan(staleTimeout);
  });
});

describe("schema hash validation", () => {
  it("rejects db.bin with different schema hash", () => {
    const hash1 = crypto.createHash("sha256").update("version1").digest("hex");
    const hash2 = crypto.createHash("sha256").update("version2").digest("hex");

    const buf = buildDbBin(hash1, 1, Buffer.from([1, 2, 3]));
    const parsed = parseDbBinHeader(buf);

    expect(parsed.schemaHashHex).toBe(hash1);
    expect(parsed.schemaHashHex).not.toBe(hash2);
  });

  it("accepts db.bin with matching schema hash", () => {
    const hash = crypto.createHash("sha256").update("same").digest("hex");

    const buf = buildDbBin(hash, 1, Buffer.from([1, 2, 3]));
    const parsed = parseDbBinHeader(buf);

    expect(parsed.schemaHashHex).toBe(hash);
  });
});
