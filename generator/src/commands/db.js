/**
 * Database CLI commands for elm-pages.
 */

import * as fs from "node:fs";
import * as path from "node:path";

const DB_GITIGNORE_ENTRIES = ["db.bin", "db.bin.lock", "db.bin.backup", "db/schema-history/"];

/**
 * Safely parse a JSON file, throwing a structured error on failure.
 * @param {string} filePath
 * @returns {any}
 */
function readJsonFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  try {
    return JSON.parse(raw);
  } catch (e) {
    throw {
      title: "Invalid JSON",
      message: `Failed to parse ${filePath}: ${e.message}`,
    };
  }
}

function ensureDbGitignoreEntries(cwd) {
  const dotGitignorePath = path.resolve(cwd, ".gitignore");
  const legacyGitignorePath = path.resolve(cwd, "gitignore");
  const gitignorePath = fs.existsSync(dotGitignorePath)
    ? dotGitignorePath
    : fs.existsSync(legacyGitignorePath)
    ? legacyGitignorePath
    : dotGitignorePath;

  const existing = fs.existsSync(gitignorePath)
    ? fs.readFileSync(gitignorePath, "utf8")
    : "";
  const lines = existing.split(/\r?\n/);
  const existingEntries = new Set(lines.map((line) => line.trim()));
  const missing = DB_GITIGNORE_ENTRIES.filter(
    (entry) => !existingEntries.has(entry)
  );

  if (missing.length === 0) {
    return { path: gitignorePath, added: [] };
  }

  let next = existing;
  if (next.length > 0 && !next.endsWith("\n")) {
    next += "\n";
  }
  next += missing.join("\n") + "\n";
  fs.writeFileSync(gitignorePath, next);

  return { path: gitignorePath, added: missing };
}

/**
 * elm-pages db init
 * Generates a boilerplate script/Db.elm if it doesn't exist.
 */
export async function init() {
  // Look for an elm.json in the current directory or script/ subdirectory
  const candidates = [
    path.resolve("script/src/Db.elm"),
    path.resolve("src/Db.elm"),
  ];

  // Check elm.json source directories
  const elmJsonPath = path.resolve("elm.json");
  const scriptElmJsonPath = path.resolve("script/elm.json");

  let targetPath = null;

  if (fs.existsSync(scriptElmJsonPath)) {
    const elmJson = readJsonFile(scriptElmJsonPath);
    const sourceDirs = elmJson["source-directories"] || [];
    if (sourceDirs.length > 0) {
      targetPath = path.resolve("script", sourceDirs[0], "Db.elm");
    }
  } else if (fs.existsSync(elmJsonPath)) {
    const elmJson = readJsonFile(elmJsonPath);
    const sourceDirs = elmJson["source-directories"] || [];
    if (sourceDirs.length > 0) {
      targetPath = path.resolve(sourceDirs[0], "Db.elm");
    }
  }

  if (!targetPath) {
    targetPath = candidates[0];
  }

  const gitignoreUpdate = ensureDbGitignoreEntries(process.cwd());

  if (fs.existsSync(targetPath)) {
    console.log(`Db.elm already exists at ${path.relative(process.cwd(), targetPath) || targetPath}.`);
    if (gitignoreUpdate.added.length > 0) {
      console.log(
        `Updated ${path.relative(process.cwd(), gitignoreUpdate.path)} with: ${gitignoreUpdate.added.join(", ")}`
      );
    }
    return;
  }

  const dbTemplate = `module Db exposing (Db)


type alias Db =
    { counter : Int
    }
`;

  const v1Template = `module Db.Migrate.V1 exposing (migrate, seed)

import Db


seed : () -> Db.Db
seed () =
    { counter = 0
    }


migrate : () -> Db.Db
migrate =
    seed
`;

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, dbTemplate);

  // Create V1 migration file
  const runtimeDir = process.cwd();
  const v1MigrationDir = path.join(runtimeDir, "db", "Db", "Migrate");
  const v1MigrationPath = path.join(v1MigrationDir, "V1.elm");
  fs.mkdirSync(v1MigrationDir, { recursive: true });
  fs.writeFileSync(v1MigrationPath, v1Template);

  console.log(`\nCreated:`);
  console.log(`  ${path.relative(process.cwd(), targetPath)}`);
  console.log(`  ${path.relative(process.cwd(), v1MigrationPath)}`);

  if (gitignoreUpdate.added.length > 0) {
    console.log(
      `\nUpdated ${path.relative(process.cwd(), gitignoreUpdate.path)} with: ${gitignoreUpdate.added.join(", ")}`
    );
  }
  console.log(
    "\nNext steps:"
  );
  console.log(
    "  1. Edit the Db type alias to define your database schema"
  );
  console.log(
    "  2. Update the V1 seed in db/Db/Migrate/V1.elm to provide the initial value"
  );
  console.log(
    "  3. Import Pages.Db in your scripts to read and write data"
  );
}

/**
 * elm-pages db status
 * Shows database status: Db module location, db.bin info, schema version, compatibility.
 */
export async function status() {
  const cwd = process.cwd();
  const { parseDbBinHeader } = await import("../db-bin-format.js");
  const { readSchemaVersion, computeSchemaHash } = await import("../db-schema.js");
  const { validateMigrationChain } = await import("../db-migrate.js");

  let dbBinVersion = 0;

  // Find Db.elm
  let dbElmPath = null;
  const elmJsonCandidates = [
    path.resolve(cwd, "script/elm.json"),
    path.resolve(cwd, "elm.json"),
  ];
  for (const elmJsonPath of elmJsonCandidates) {
    if (fs.existsSync(elmJsonPath)) {
      const elmJson = readJsonFile(elmJsonPath);
      const sourceDirs = elmJson["source-directories"] || [];
      const base = path.dirname(elmJsonPath);
      for (const dir of sourceDirs) {
        const candidate = path.resolve(base, dir, "Db.elm");
        if (fs.existsSync(candidate)) {
          dbElmPath = candidate;
          break;
        }
      }
      if (dbElmPath) break;
    }
  }

  console.log("elm-pages database status\n");

  // Db module
  if (dbElmPath) {
    console.log(`  Db module:       ${path.relative(cwd, dbElmPath)}`);
  } else {
    console.log("  Db module:       not found");
    console.log("                   Run 'elm-pages db init' to create one.");
  }

  // Schema version (derived from db/Db/Migrate/V*.elm files)
  const schemaVersion = await readSchemaVersion(cwd);
  console.log(`  Schema version:  ${schemaVersion}`);

  // db.bin
  const dbBinPath = path.resolve(cwd, "db.bin");
  if (fs.existsSync(dbBinPath)) {
    const stat = fs.statSync(dbBinPath);
    const sizeKb = (stat.size / 1024).toFixed(1);
    console.log(`  db.bin:          ${sizeKb} KB`);

    try {
      const contents = fs.readFileSync(dbBinPath);
      const parsed = parseDbBinHeader(contents);
      dbBinVersion = parsed.schemaVersion;

      const formatLabel = parsed.formatVersion === 0 ? "v1 (legacy)" : `v${parsed.formatVersion}`;
      console.log(`  Format:          ${formatLabel}`);
      console.log(`  Stored version:  ${parsed.schemaVersion}`);
      console.log(`  Stored hash:     ${parsed.schemaHashHex.slice(0, 16)}...`);

      // Compatibility check
      if (dbElmPath) {
        const currentHash = await computeSchemaHash(dbElmPath);
        if (parsed.schemaHashHex === currentHash) {
          console.log("  Compatibility:   matching");
        } else {
          console.log("  Compatibility:   MISMATCHED (source hash differs)");
          console.log(`  Current hash:    ${currentHash.slice(0, 16)}...`);
        }
      }

    } catch (error) {
      console.log(`  Status:          ERROR - ${error.title || error.message || error}`);
    }
  } else {
    console.log("  db.bin:          not found (will be created on first write)");
  }

  // Lock file (default path, with legacy fallback)
  const lockPathCandidates = [
    path.resolve(cwd, "db.bin.lock"),
    path.resolve(cwd, "db.lock"),
  ];
  const dbLockPath = lockPathCandidates.find((candidate) =>
    fs.existsSync(candidate)
  );
  if (dbLockPath) {
    try {
      const lockData = JSON.parse(fs.readFileSync(dbLockPath, "utf8"));
      console.log(
        `  Lock:            held by PID ${lockData.pid} (since ${lockData.createdAt}, ${path.basename(
          dbLockPath
        )})`
      );
    } catch (_) {
      console.log(`  Lock:            present (${path.basename(dbLockPath)}, unreadable)`);
    }
  }

  // Migration chain
  if (schemaVersion > 1) {
    if (dbBinVersion >= schemaVersion) {
      console.log("  Migration chain: up to date");
    } else {
      const validation = await validateMigrationChain(cwd, dbBinVersion || 1, schemaVersion);
      console.log("  Migration chain:");
      for (let v = 1; v < schemaVersion; v++) {
        let label;
        if (dbBinVersion >= v + 1) {
          label = "applied";
        } else if (validation.missingFiles && validation.missingFiles.includes(`Db/Migrate/V${v + 1}.elm`)) {
          label = "missing";
        } else if (validation.unimplemented && validation.unimplemented.includes(`Db/Migrate/V${v + 1}.elm`)) {
          label = "pending          (unimplemented stub)";
        } else {
          label = "ready";
        }
        console.log(`    V${v} → V${v + 1}    ${label}`);
      }
      if (validation.unimplemented && validation.unimplemented.length > 0) {
        console.log(`\n  Implement the migration stubs, then run \`elm-pages db migrate\`.`);
      } else if (validation.missingFiles && validation.missingFiles.length > 0) {
        console.log(`\n  Run \`elm-pages db migrate\` to create missing migration files.`);
      } else {
        console.log(`\n  Run \`elm-pages db migrate\` to apply pending migrations.`);
      }
    }
  }

  // Exit code 1 when migrations are pending
  if (schemaVersion > 1 && dbBinVersion > 0 && dbBinVersion < schemaVersion) {
    process.exitCode = 1;
  }

  console.log("");
}

/**
 * elm-pages db migrate [--force-stale-snapshot]
 * Idempotent command that creates or applies database migrations based on state:
 * - No pending migration → create scaffold (snapshot + stub)
 * - Pending migration, stubs implemented → apply the migration
 * - Pending migration, stubs not implemented → friendly guidance
 */
export async function migrate(options = {}) {
  const cwd = process.cwd();
  const {
    readSchemaVersion,
    computeSchemaHash,
    loadSchemaSource,
  } = await import("../db-schema.js");
  const { parseDbBinHeader } = await import("../db-bin-format.js");
  const {
    createSnapshot, detectMigrationNeeded,
    validateMigrationChain, applyMigration,
  } = await import("../db-migrate.js");

  // Find Db.elm
  const dbElmPath = await findDbElmForMigration(cwd);
  if (!dbElmPath) {
    throw new Error(
      "Could not find Db.elm. Run `elm-pages db init` first."
    );
  }

  const dbSource = fs.readFileSync(dbElmPath, "utf8");
  const dbElmDisplayPath = path.relative(cwd, dbElmPath) || dbElmPath;
  const currentVersion = await readSchemaVersion(cwd);

  // Detect current state
  const migrationStatus = await detectMigrationNeeded(cwd);

  if (migrationStatus.action === "up-to-date" || migrationStatus.action === "no-db") {
    let snapshotSource = dbSource;

    // Guardrail: prevent stale snapshots when Db.elm was already edited
    // while db.bin/schema-version are still at the old version.
    if (migrationStatus.action === "up-to-date") {
      const dbBinPath = path.resolve(cwd, "db.bin");
      const dbBinContents = fs.readFileSync(dbBinPath);
      const parsed = parseDbBinHeader(dbBinContents);
      const currentHash = await computeSchemaHash(dbElmPath);

      if (
        parsed.schemaVersion === currentVersion &&
        parsed.schemaHashHex !== currentHash
      ) {
        const historicalSource = await loadSchemaSource(cwd, parsed.schemaHashHex);
        if (historicalSource) {
          snapshotSource = historicalSource;
          console.log("\nDetected stale Db.elm state; recovering old schema from db/schema-history.");
        } else if (!options.forceStaleSnapshot) {
          console.log(`\nCannot create migration files yet.`);
          console.log(`\n${dbElmDisplayPath} was changed before the old schema snapshot was captured.`);
          console.log(`\nCurrent state:`);
          console.log(`  db.bin is at V${currentVersion}`);
          console.log(`  Schema version (from migration files) is V${currentVersion}`);
          console.log(`  ${dbElmDisplayPath} has a different schema hash`);
          console.log(`  Missing: db/schema-history/${parsed.schemaHashHex}.elm`);
          console.log(
            `\nContinuing now would snapshot the wrong schema into db/Db/V${currentVersion}.elm.`
          );
          console.log(`\nTo fix:`);
          console.log(`  1. Restore ${dbElmDisplayPath} to the schema currently stored in db.bin`);
          console.log(
            `  2. Run \`elm-pages db migrate\` to create the V${currentVersion} snapshot + V${currentVersion + 1} stub`
          );
          console.log(
            `  3. Re-apply your Db.elm changes and implement db/Db/Migrate/V${currentVersion + 1}.elm`
          );
          console.log(`\nOverride (not recommended):`);
          console.log(`  elm-pages db migrate --force-stale-snapshot`);
          console.log(
            `\nTip: after any successful write, stale snapshot recovery uses db/schema-history/<hash>.elm automatically.`
          );
          process.exitCode = 1;
          return;
        }
      }
    }

    // Path A: No pending migration → create scaffold
    await createSnapshot(cwd, snapshotSource, currentVersion);
    const newVersion = currentVersion + 1;

    console.log(`\nCreated migration V${currentVersion} -> V${newVersion}:`);
    console.log(`  Snapshot: db/Db/V${currentVersion}.elm`);
    console.log(`  Stub:     db/Db/Migrate/V${newVersion}.elm`);
    console.log(`\nNext steps:`);
    console.log(`  1. Edit db/Db/Migrate/V${newVersion}.elm to implement the migration`);
    console.log(`  2. Replace the todo_implement_ sentinel with your migration logic`);
    console.log(`  3. Run \`elm-pages db migrate\` again to apply the migration`);
  } else if (migrationStatus.action === "migrate") {
    // Pending migration: validate chain
    const validation = await validateMigrationChain(
      cwd,
      migrationStatus.fromVersion,
      migrationStatus.toVersion
    );

    if (validation.valid) {
      // Path B: Stubs implemented → apply migration
      await applyMigration(cwd, migrationStatus.fromVersion, migrationStatus.toVersion);
      console.log(`\nMigration applied: V${migrationStatus.fromVersion} -> V${migrationStatus.toVersion}`);
    } else {
      // Path C: Stubs not implemented → friendly guidance
      console.log(`\nPending migration: V${migrationStatus.fromVersion} -> V${migrationStatus.toVersion}`);
      if (validation.missingFiles && validation.missingFiles.length > 0) {
        console.log(`\nMissing files:`);
        for (const f of validation.missingFiles) {
          console.log(`  db/${f}`);
        }
      }
      if (validation.unimplemented && validation.unimplemented.length > 0) {
        console.log(`\nUnimplemented migration stubs:`);
        for (const f of validation.unimplemented) {
          console.log(`  db/${f}`);
          const vMatch = f.match(/V(\d+)\.elm$/);
          if (vMatch) {
            const v = parseInt(vMatch[1], 10);
            if (v === 1) {
              console.log(`    Expected signature: seed : () -> Db.Db`);
            } else {
              console.log(`    Expected signature: migrate : Db.V${v - 1}.Db -> Db.Db`);
            }
          }
        }
      }
      console.log(`\nImplement the migration logic and run \`elm-pages db migrate\` again to apply.`);
      process.exitCode = 1;
    }
  } else if (migrationStatus.action === "error") {
    throw new Error(
      `db.bin is at a newer version than the schema. This should not happen.\n` +
      `Delete db.bin and db.bin.lock to start fresh, or restore your schema files.`
    );
  }
}

/**
 * Find Db.elm for migration (similar to status command).
 * @param {string} cwd
 * @returns {Promise<string|null>}
 */
async function findDbElmForMigration(cwd) {
  const elmJsonCandidates = [
    path.resolve(cwd, "script/elm.json"),
    path.resolve(cwd, "elm.json"),
  ];
  for (const elmJsonPath of elmJsonCandidates) {
    if (fs.existsSync(elmJsonPath)) {
      const elmJson = readJsonFile(elmJsonPath);
      const sourceDirs = elmJson["source-directories"] || [];
      const base = path.dirname(elmJsonPath);
      for (const dir of sourceDirs) {
        const candidate = path.resolve(base, dir, "Db.elm");
        if (fs.existsSync(candidate)) {
          return candidate;
        }
      }
    }
  }
  return null;
}
