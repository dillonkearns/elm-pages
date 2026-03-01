/**
 * Database CLI commands for elm-pages.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as readline from "readline";

/**
 * elm-pages db reset [--force]
 * Deletes db.bin and db.lock to start fresh.
 */
export async function reset(options) {
  const cwd = process.cwd();
  const dbBinPath = path.resolve(cwd, "db.bin");
  const dbLockPath = path.resolve(cwd, "db.lock");

  const dbBinExists = fs.existsSync(dbBinPath);
  const dbLockExists = fs.existsSync(dbLockPath);

  if (!dbBinExists && !dbLockExists) {
    console.log("No db.bin or db.lock found. Nothing to reset.");
    return;
  }

  if (!options.force) {
    const confirmed = await confirm(
      "This will delete your local database (db.bin). Are you sure?"
    );
    if (!confirmed) {
      console.log("Aborted.");
      return;
    }
  }

  if (dbBinExists) {
    fs.unlinkSync(dbBinPath);
    console.log("Deleted db.bin");
  }
  if (dbLockExists) {
    fs.unlinkSync(dbLockPath);
    console.log("Deleted db.lock");
  }
  console.log("Database reset complete.");
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
    const elmJson = JSON.parse(fs.readFileSync(scriptElmJsonPath, "utf8"));
    const sourceDirs = elmJson["source-directories"] || [];
    if (sourceDirs.length > 0) {
      targetPath = path.resolve("script", sourceDirs[0], "Db.elm");
    }
  } else if (fs.existsSync(elmJsonPath)) {
    const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
    const sourceDirs = elmJson["source-directories"] || [];
    if (sourceDirs.length > 0) {
      targetPath = path.resolve(sourceDirs[0], "Db.elm");
    }
  }

  if (!targetPath) {
    targetPath = candidates[0];
  }

  if (fs.existsSync(targetPath)) {
    console.log(`Db.elm already exists at ${targetPath}`);
    return;
  }

  const template = `module Db exposing (Db, init)


type alias Db =
    { counter : Int
    }


init : Db
init =
    { counter = 0
    }
`;

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, template);
  console.log(`Created ${targetPath}`);
  console.log(
    "\nEdit the Db type alias to define your database schema, then import Pages.Db in your scripts."
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

  // Find Db.elm
  let dbElmPath = null;
  const elmJsonCandidates = [
    path.resolve(cwd, "script/elm.json"),
    path.resolve(cwd, "elm.json"),
  ];
  for (const elmJsonPath of elmJsonCandidates) {
    if (fs.existsSync(elmJsonPath)) {
      const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
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

  // Schema version (from .elm-pages-db/schema-version.json)
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

      if (parsed.schemaVersion !== schemaVersion) {
        console.log(`\n  Warning: stored schema version (${parsed.schemaVersion}) differs from current (${schemaVersion}).`);
      }
    } catch (error) {
      console.log(`  Status:          ERROR - ${error.title || error.message || error}`);
    }
  } else {
    console.log("  db.bin:          not found (will be created on first write)");
  }

  // Lock file
  const dbLockPath = path.resolve(cwd, "db.lock");
  if (fs.existsSync(dbLockPath)) {
    try {
      const lockData = JSON.parse(fs.readFileSync(dbLockPath, "utf8"));
      console.log(`  Lock:            held by PID ${lockData.pid} (since ${lockData.createdAt})`);
    } catch (_) {
      console.log("  Lock:            present (unreadable)");
    }
  }

  // Migrations directory
  const migrationsDir = path.resolve(cwd, ".elm-pages-db");
  if (fs.existsSync(migrationsDir)) {
    const entries = fs.readdirSync(migrationsDir);
    const dbDir = path.join(migrationsDir, "Db");
    if (fs.existsSync(dbDir)) {
      const snapshots = fs.readdirSync(dbDir).filter(f => f.match(/^V\d+\.elm$/));
      if (snapshots.length > 0) {
        console.log(`  Snapshots:       ${snapshots.join(", ")}`);
      }
      const migrateDir = path.join(dbDir, "Migrate");
      if (fs.existsSync(migrateDir)) {
        const migrations = fs.readdirSync(migrateDir).filter(f => f.endsWith(".elm"));
        if (migrations.length > 0) {
          console.log(`  Migrations:      ${migrations.join(", ")}`);
        }
      }
    }
  }

  console.log("");
}

/**
 * elm-pages db migrate
 * Idempotent command that creates or applies database migrations based on state:
 * - No pending migration → create scaffold (snapshot + stub)
 * - Pending migration, stubs implemented → apply the migration
 * - Pending migration, stubs not implemented → friendly guidance
 */
export async function migrate() {
  const cwd = process.cwd();
  const { readSchemaVersion } = await import("../db-schema.js");
  const {
    createSnapshot, writeMigrateChain, detectMigrationNeeded,
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
  const currentVersion = await readSchemaVersion(cwd);

  // Detect current state
  const migrationStatus = await detectMigrationNeeded(cwd);

  if (migrationStatus.action === "up-to-date" || migrationStatus.action === "no-db") {
    // Path A: No pending migration → create scaffold
    await createSnapshot(cwd, dbSource, currentVersion);
    const newVersion = currentVersion + 1;
    await writeMigrateChain(cwd, newVersion);

    console.log(`\nCreated migration V${currentVersion} -> V${newVersion}:`);
    console.log(`  Snapshot: .elm-pages-db/Db/V${currentVersion}.elm`);
    console.log(`  Stub:     .elm-pages-db/Db/Migrate/V${newVersion}.elm`);
    console.log(`  Chain:    .elm-pages-db/MigrateChain.elm`);
    console.log(`\nNext steps:`);
    console.log(`  1. Edit .elm-pages-db/Db/Migrate/V${newVersion}.elm to implement the migration`);
    console.log(`  2. Replace the todo_implement_migration sentinel with your migration logic`);
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
          console.log(`  .elm-pages-db/${f}`);
        }
      }
      if (validation.unimplemented && validation.unimplemented.length > 0) {
        console.log(`\nUnimplemented migration stubs:`);
        for (const f of validation.unimplemented) {
          console.log(`  .elm-pages-db/${f}`);
        }
      }
      console.log(`\nImplement the migration logic and run \`elm-pages db migrate\` again to apply.`);
    }
  } else if (migrationStatus.action === "error") {
    throw new Error(
      `db.bin is at a newer version than the schema. This should not happen.\n` +
      `Run \`elm-pages db reset\` to start fresh, or restore your schema files.`
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
      const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
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

/**
 * Prompt user for yes/no confirmation.
 * @param {string} message
 * @returns {Promise<boolean>}
 */
function confirm(message) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(`${message} [y/N] `, (answer) => {
      rl.close();
      resolve(answer.toLowerCase() === "y" || answer.toLowerCase() === "yes");
    });
  });
}
