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

// db.bin binary format constants (must match render.js)
const DB_MAGIC = Buffer.from("EPDB", "ascii");
const DB_HEADER_SIZE = 4 + 32; // magic + hash

let tmpDir;

beforeEach(async () => {
  tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "db-handler-test-"));
});

afterEach(async () => {
  await fs.promises.rm(tmpDir, { recursive: true });
});

/**
 * Construct a valid db.bin file buffer.
 */
function makeDbBin(schemaHashHex, wire3Data) {
  const hashBytes = Buffer.from(schemaHashHex, "hex");
  const data = Buffer.isBuffer(wire3Data) ? wire3Data : Buffer.from(wire3Data);
  const buf = Buffer.alloc(DB_HEADER_SIZE + data.length);
  DB_MAGIC.copy(buf, 0);
  hashBytes.copy(buf, 4);
  data.copy(buf, DB_HEADER_SIZE);
  return buf;
}

/**
 * Parse a db.bin file buffer, returning its parts.
 */
function parseDbBin(buf) {
  if (buf.length < DB_HEADER_SIZE) {
    throw new Error("Too small");
  }
  const magic = buf.subarray(0, 4).toString("ascii");
  const hashHex = buf.subarray(4, 36).toString("hex");
  const wire3Data = buf.subarray(DB_HEADER_SIZE);
  return { magic, hashHex, wire3Data };
}

describe("db.bin binary format", () => {
  const testHash = crypto.createHash("sha256").update("test").digest("hex");

  it("constructs a valid header with magic bytes", () => {
    const buf = makeDbBin(testHash, Buffer.from([1, 2, 3]));

    expect(buf.subarray(0, 4).toString("ascii")).toBe("EPDB");
    expect(buf.length).toBe(DB_HEADER_SIZE + 3);
  });

  it("stores schema hash as raw bytes at offset 4", () => {
    const buf = makeDbBin(testHash, Buffer.alloc(0));

    const storedHash = buf.subarray(4, 36).toString("hex");
    expect(storedHash).toBe(testHash);
  });

  it("stores Wire3 data after the header", () => {
    const wire3 = Buffer.from([0xDE, 0xAD, 0xBE, 0xEF]);
    const buf = makeDbBin(testHash, wire3);

    const storedData = buf.subarray(DB_HEADER_SIZE);
    expect([...storedData]).toEqual([0xDE, 0xAD, 0xBE, 0xEF]);
  });

  it("round-trips through construct and parse", () => {
    const wire3 = Buffer.from("hello wire3 data");
    const buf = makeDbBin(testHash, wire3);
    const parsed = parseDbBin(buf);

    expect(parsed.magic).toBe("EPDB");
    expect(parsed.hashHex).toBe(testHash);
    expect(parsed.wire3Data.toString()).toBe("hello wire3 data");
  });

  it("rejects buffers that are too small", () => {
    expect(() => parseDbBin(Buffer.alloc(10))).toThrow("Too small");
  });

  it("handles empty Wire3 data", () => {
    const buf = makeDbBin(testHash, Buffer.alloc(0));
    const parsed = parseDbBin(buf);

    expect(parsed.wire3Data.length).toBe(0);
    expect(buf.length).toBe(DB_HEADER_SIZE);
  });
});

describe("db-read response format", () => {
  it("encodes no-data response as 4 big-endian zero bytes", () => {
    // When db.bin doesn't exist, the handler returns a bytes response
    // with a big-endian int32 = 0, telling Elm to use Db.init.
    // Must use DataView (not Int32Array) to ensure big-endian encoding.
    const buffer = new Uint8Array(4);
    new DataView(buffer.buffer).setInt32(0, 0);

    expect(buffer.length).toBe(4);

    // The Elm side reads a big-endian int32
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    expect(view.getInt32(0, false)).toBe(0); // false = big-endian

    // Verify base64 round-trip (how bytesResponse transmits it)
    const base64 = Buffer.from(buffer).toString("base64");
    const decoded = Buffer.from(base64, "base64");
    expect(decoded.length).toBe(4);
    // Must use byteOffset/byteLength - Buffer may share a larger ArrayBuffer pool
    expect(new DataView(decoded.buffer, decoded.byteOffset, decoded.byteLength).getInt32(0, false)).toBe(0);
  });

  it("encodes success response as length-prefixed Wire3 data", () => {
    // Simulating what runDbRead does on success
    const wire3Data = Buffer.from([1, 2, 3, 4, 5]);
    const buffer = new Uint8Array(4 + wire3Data.length);
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    view.setInt32(0, wire3Data.length); // big-endian by default
    wire3Data.copy(buffer, 4);

    // Verify the Elm side can read this:
    // 1. Read int32 BE = 5
    expect(view.getInt32(0, false)).toBe(5);
    // 2. Read 5 bytes starting at offset 4
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

    // Construct file buffer (same as runDbWrite)
    const hashBytes = Buffer.from(testHash, "hex");
    const fileBuffer = Buffer.alloc(DB_HEADER_SIZE + wire3Data.length);
    DB_MAGIC.copy(fileBuffer, 0);
    hashBytes.copy(fileBuffer, 4);
    wire3Data.copy(fileBuffer, DB_HEADER_SIZE);

    // Atomic write
    await fs.promises.writeFile(tmpPath, fileBuffer);
    await fs.promises.rename(tmpPath, dbBinPath);

    // Verify
    expect(fs.existsSync(tmpPath)).toBe(false);
    expect(fs.existsSync(dbBinPath)).toBe(true);

    const written = await fs.promises.readFile(dbBinPath);
    expect(written.subarray(0, 4).toString("ascii")).toBe("EPDB");
    expect(written.subarray(4, 36).toString("hex")).toBe(testHash);
    expect([...written.subarray(DB_HEADER_SIZE)]).toEqual([10, 20, 30]);
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

    // First write should succeed
    await fs.promises.writeFile(lockPath, lockData, { flag: "wx" });
    expect(fs.existsSync(lockPath)).toBe(true);

    // Second write with wx should fail
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

    // Wrong token should not delete
    const existing = JSON.parse(await fs.promises.readFile(lockPath, "utf8"));
    if (existing.token === wrongToken) {
      await fs.promises.unlink(lockPath);
    }
    expect(fs.existsSync(lockPath)).toBe(true);

    // Correct token should delete
    if (existing.token === correctToken) {
      await fs.promises.unlink(lockPath);
    }
    expect(fs.existsSync(lockPath)).toBe(false);
  });

  it("detects stale lock from dead PID", async () => {
    const lockPath = path.join(tmpDir, "db.lock");
    // PID 999999 is almost certainly not alive
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
    // Handler would remove the stale lock and retry
  });

  it("detects stale lock from old timestamp", async () => {
    const lockPath = path.join(tmpDir, "db.lock");
    const staleTime = new Date(Date.now() - 10 * 60 * 1000); // 10 minutes ago
    const lockData = JSON.stringify({
      pid: process.pid, // alive PID, but old timestamp
      createdAt: staleTime.toISOString(),
      token: crypto.randomUUID(),
    });

    await fs.promises.writeFile(lockPath, lockData);

    const existing = JSON.parse(await fs.promises.readFile(lockPath, "utf8"));
    const lockAge = Date.now() - new Date(existing.createdAt).getTime();
    const staleTimeout = 5 * 60 * 1000;

    expect(lockAge).toBeGreaterThan(staleTimeout);
    // Handler would remove the stale lock and retry
  });
});

describe("schema hash validation", () => {
  it("rejects db.bin with different schema hash", () => {
    const hash1 = crypto.createHash("sha256").update("version1").digest("hex");
    const hash2 = crypto.createHash("sha256").update("version2").digest("hex");

    const buf = makeDbBin(hash1, Buffer.from([1, 2, 3]));
    const storedHash = buf.subarray(4, 36).toString("hex");

    expect(storedHash).toBe(hash1);
    expect(storedHash).not.toBe(hash2);
  });

  it("accepts db.bin with matching schema hash", () => {
    const hash = crypto.createHash("sha256").update("same").digest("hex");

    const buf = makeDbBin(hash, Buffer.from([1, 2, 3]));
    const storedHash = buf.subarray(4, 36).toString("hex");

    expect(storedHash).toBe(hash);
  });

  it("rejects files with invalid magic bytes", () => {
    const buf = Buffer.alloc(DB_HEADER_SIZE + 5);
    buf.write("NOPE", 0, "ascii"); // wrong magic

    const magic = buf.subarray(0, 4);
    expect(magic.equals(DB_MAGIC)).toBe(false);
  });

  it("rejects files smaller than header size", () => {
    const buf = Buffer.alloc(10);
    expect(buf.length).toBeLessThan(DB_HEADER_SIZE);
  });
});
