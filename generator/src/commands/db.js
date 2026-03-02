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
  console.log(
    "Db.init is your V1 seed. After your first migration, fresh installs seed from Db.V1.init through the migration chain."
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
          console.log("\nDetected stale Db.elm state; recovering old schema from .elm-pages-db/schema-history.");
        } else if (!options.forceStaleSnapshot) {
          console.log(`\nI can't create migration files yet.\n`);
          console.log(`Reason: your current Db file was changed before the old schema snapshot was captured.`);
          console.log(`\nI found:`);
          console.log(`  - db.bin is at V${currentVersion}`);
          console.log(`  - .elm-pages-db/schema-version.json is at V${currentVersion}`);
          console.log(`  - ${dbElmDisplayPath} has a different schema hash`);
          console.log(`  - Missing: .elm-pages-db/schema-history/${parsed.schemaHashHex}.elm`);
          console.log(
            `\nIf I continue now, .elm-pages-db/Db/V${currentVersion}.elm would contain your new schema (wrong snapshot).`
          );
          console.log(`\nDo this:`);
          console.log(`  1. Restore ${dbElmDisplayPath} to the schema currently stored in db.bin`);
          console.log(
            `  2. Run \`elm-pages db migrate\` to create the V${currentVersion} snapshot + V${currentVersion + 1} stub`
          );
          console.log(
            `  3. Re-apply your Db.elm changes and implement .elm-pages-db/Db/Migrate/V${currentVersion + 1}.elm`
          );
          console.log(`\nUnsafe override (not recommended):`);
          console.log(`  elm-pages db migrate --force-stale-snapshot`);
          console.log(
            `\nTip: after any successful write, stale snapshot recovery can use .elm-pages-db/schema-history/<hash>.elm automatically.`
          );
          process.exitCode = 1;
          return;
        }
      }
    }

    // Path A: No pending migration → create scaffold
    await createSnapshot(cwd, snapshotSource, currentVersion);
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
    if (currentVersion === 1) {
      console.log(
        `\nAfter V1 -> V2 is in place, fresh installs seed from Db.V1.init through migrations, so current Db.init can be removed.`
      );
    }
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
          const vMatch = f.match(/V(\d+)\.elm$/);
          if (vMatch) {
            const v = parseInt(vMatch[1], 10);
            console.log(`  Expected: migrate : Db.V${v - 1}.Db -> Db.Db`);
          }
        }
      }
      console.log(`\nImplement the migration logic and run \`elm-pages db migrate\` again to apply.`);
      process.exitCode = 1;
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
