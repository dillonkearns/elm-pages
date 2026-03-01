/**
 * Schema hash computation for the elm-pages built-in database.
 *
 * Phase 1: Source-text hash only.
 * Phase 2 will add deep compare (compiled-codec hash).
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs";

/**
 * Compute a SHA-256 hash of the Db.elm source text.
 * Returns a 64-character hex string.
 * @param {string} dbElmPath - Absolute path to Db.elm
 * @returns {Promise<string>}
 */
export async function computeSchemaHash(dbElmPath) {
  const dbSource = await fs.promises.readFile(dbElmPath, "utf8");
  return crypto.createHash("sha256").update(dbSource).digest("hex");
}

/**
 * Convert a hex hash string to a raw byte Buffer (32 bytes for SHA-256).
 * @param {string} hexHash - 64-character hex string
 * @returns {Buffer}
 */
export function hashToBytes(hexHash) {
  return Buffer.from(hexHash, "hex");
}

/**
 * Convert raw hash bytes to a hex string.
 * @param {Buffer} bytes - 32-byte buffer
 * @returns {string}
 */
export function bytesToHash(bytes) {
  return Buffer.from(bytes).toString("hex");
}
