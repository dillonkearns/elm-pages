/**
 * Schema hash computation and deep compare for the elm-pages built-in database.
 *
 * Fast path: SHA-256 of Db.elm source text (instant).
 * Deep compare: When source text differs, compile a witness module and hash
 * the compiled JS to detect whether the change is structural or cosmetic.
 */

import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";

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

// --- Schema meta cache ---

const SCHEMA_META_FILENAME = "db-schema-meta.json";

/**
 * Load the cached schema meta from .elm-pages/db-schema-meta.json.
 * Returns null if file doesn't exist.
 * @param {string} projectDirectory
 * @returns {Promise<{sourceHash: string, compiledHash: string} | null>}
 */
export async function loadSchemaMeta(projectDirectory) {
  const metaPath = path.join(projectDirectory, ".elm-pages", SCHEMA_META_FILENAME);
  try {
    const content = await fs.promises.readFile(metaPath, "utf8");
    return JSON.parse(content);
  } catch (_) {
    return null;
  }
}

/**
 * Save the schema meta cache.
 * @param {string} projectDirectory
 * @param {string} sourceHash - SHA-256 of current Db.elm source
 * @param {string} compiledHash - SHA-256 of compiled witness JS
 */
export async function saveSchemaMeta(projectDirectory, sourceHash, compiledHash) {
  const dir = path.join(projectDirectory, ".elm-pages");
  await fs.promises.mkdir(dir, { recursive: true });
  const metaPath = path.join(dir, SCHEMA_META_FILENAME);
  await fs.promises.writeFile(
    metaPath,
    JSON.stringify({ sourceHash, compiledHash }, null, 2) + "\n"
  );
}

// --- Schema version tracking ---

const SCHEMA_VERSION_DIR = ".elm-pages-db";
const SCHEMA_VERSION_FILENAME = "schema-version.json";

/**
 * Read the current schema version from .elm-pages-db/schema-version.json.
 * Returns 1 if the file doesn't exist (initial version).
 * @param {string} projectDirectory
 * @returns {Promise<number>}
 */
export async function readSchemaVersion(projectDirectory) {
  const versionPath = path.join(projectDirectory, SCHEMA_VERSION_DIR, SCHEMA_VERSION_FILENAME);
  try {
    const content = await fs.promises.readFile(versionPath, "utf8");
    const parsed = JSON.parse(content);
    return parsed.version || 1;
  } catch (_) {
    return 1;
  }
}

/**
 * Write the schema version to .elm-pages-db/schema-version.json.
 * Creates the directory if needed.
 * @param {string} projectDirectory
 * @param {number} version
 */
export async function writeSchemaVersion(projectDirectory, version) {
  const dir = path.join(projectDirectory, SCHEMA_VERSION_DIR);
  await fs.promises.mkdir(dir, { recursive: true });
  const versionPath = path.join(dir, SCHEMA_VERSION_FILENAME);
  await fs.promises.writeFile(
    versionPath,
    JSON.stringify({ version }, null, 2) + "\n"
  );
}

// --- Deep compare ---

/**
 * Generate the Elm source for a witness module that captures Db.w3_encode_Db.
 * The compiled output's hash is a fingerprint of the schema's binary structure.
 */
function witnessModuleSource() {
  return `module ElmPagesDbWitness exposing (main)

import Db
import Lamdera.Wire3 as Wire
import Platform

main =
    Platform.worker
        { init = \\() -> ( Db.w3_encode_Db, Cmd.none )
        , update = \\_ m -> ( m, Cmd.none )
        , subscriptions = \\_ -> Sub.none
        }
`;
}

/**
 * Compile a witness module and return the SHA-256 hash of the compiled JS.
 *
 * @param {string} compileDir - Directory with elm.json to compile in
 * @param {string} executableName - "lamdera" or "elm"
 * @returns {Promise<string>} SHA-256 hex hash of compiled JS
 */
export async function compileWitnessAndHash(compileDir, executableName) {
  // Write witness module to a temp location within the compile directory's source paths
  const witnessPath = path.join(compileDir, ".elm-pages", "ElmPagesDbWitness.elm");
  const outputPath = path.join(compileDir, ".elm-pages", "elm-pages-db-witness.js");

  try {
    await fs.promises.writeFile(witnessPath, witnessModuleSource());

    // Compile with lamdera/elm make
    const result = spawnSync(
      executableName,
      ["make", witnessPath, "--output", outputPath],
      { cwd: compileDir, stdio: ["ignore", "pipe", "pipe"] }
    );

    if (result.status !== 0) {
      const stderr = result.stderr ? result.stderr.toString() : "";
      throw {
        title: "Deep compare compilation failed",
        message: `Failed to compile witness module for schema comparison.\n${stderr}`,
      };
    }

    // Hash the compiled JS output
    const compiledJs = await fs.promises.readFile(outputPath);
    return crypto.createHash("sha256").update(compiledJs).digest("hex");
  } finally {
    // Clean up temp files
    try { await fs.promises.unlink(witnessPath); } catch (_) {}
    try { await fs.promises.unlink(outputPath); } catch (_) {}
  }
}

/**
 * Compare the current schema hash against the stored hash in db.bin.
 * Uses fast-path (source text hash) first, then deep compare if needed.
 *
 * Returns { compatible: true, updatedSourceHash } if compatible (possibly
 * after deep compare), or throws a structured error if incompatible.
 *
 * @param {string} currentSourceHash - SHA-256 of current Db.elm source
 * @param {string} storedHash - Schema hash from db.bin header
 * @param {string} projectDirectory - Project directory path
 * @param {string} executableName - "lamdera" or "elm"
 * @returns {Promise<{ compatible: boolean, needsMetaUpdate: boolean }>}
 */
export async function compareSchemaHash(currentSourceHash, storedHash, projectDirectory, executableName) {
  // Fast path: exact match
  if (currentSourceHash === storedHash) {
    return { compatible: true, needsMetaUpdate: false };
  }

  // Source hash differs. Try deep compare.
  const meta = await loadSchemaMeta(projectDirectory);

  // If we have a cached compiled hash for the stored source hash,
  // compile current and compare
  const compileDir = path.join(projectDirectory, "elm-stuff", "elm-pages");

  // Compile current schema's witness
  let currentCompiledHash;
  try {
    currentCompiledHash = await compileWitnessAndHash(compileDir, executableName);
  } catch (error) {
    // If deep compare can't compile, we can't verify — fail closed
    if (error.title) throw error;
    throw {
      title: "Schema verification failed",
      message: `Could not compile witness module to verify schema compatibility: ${error.message || error}`,
    };
  }

  // Check if we have a stored compiled hash to compare against
  if (meta && meta.compiledHash) {
    if (currentCompiledHash === meta.compiledHash) {
      // Cosmetic change only — update the source hash fingerprint
      await saveSchemaMeta(projectDirectory, currentSourceHash, currentCompiledHash);
      return { compatible: true, needsMetaUpdate: true };
    }
    // Real structural change
    return { compatible: false, needsMetaUpdate: false };
  }

  // No cached compiled hash — this is the first deep compare.
  // Save current compiled hash for future comparisons.
  await saveSchemaMeta(projectDirectory, currentSourceHash, currentCompiledHash);
  // We can't compare without a baseline, so this is incompatible
  // (the source hashes differ and we have no compiled reference)
  return { compatible: false, needsMetaUpdate: false };
}
