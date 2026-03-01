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
