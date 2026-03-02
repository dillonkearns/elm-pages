/**
 * Migration helpers for elm-pages database.
 *
 * Pure functions for snapshot/stub/chain generation,
 * plus filesystem orchestration for `elm-pages db migrate`.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { parseDbBinHeader, buildDbBin } from "./db-bin-format.js";
import { readSchemaVersion, writeSchemaVersion } from "./db-schema.js";

// --- A1: rewriteDbModuleToSnapshot ---

/**
 * Rewrite `module Db exposing (...)` to `module Db.V{N} exposing (...)`.
 * @param {string} source - The Db.elm source text
 * @param {number} version - The snapshot version number
 * @returns {string} The rewritten source
 */
export function rewriteDbModuleToSnapshot(source, version) {
  return source.replace(
    /^(module\s+)Db(\s+exposing)/m,
    `$1Db.V${version}$2`
  );
}

// --- A2: generateMigrationStub ---

/**
 * Generate a migration stub module for Db.V{from} -> Db.
 * @param {number} fromVersion - The source version
 * @param {number} toVersion - The target version
 * @returns {string} Elm source for the migration stub
 */
export function generateMigrationStub(fromVersion, toVersion) {
  return `module Db.Migrate.V${toVersion} exposing (migrate, seed)

import Db
import Db.V${fromVersion}


migrate : Db.V${fromVersion}.Db -> Db.Db
migrate old =
    todo_implement_migration_V${fromVersion}_to_V${toVersion}


seed : Db.V${fromVersion}.Db -> Db.Db
seed old =
    migrate old
`;
}

// --- A4: checkPendingMigration ---

/**
 * Check whether a migration is pending (db.bin version < schema version).
 * @param {string} projectDir - Project root directory
 * @returns {Promise<{ pending: boolean, dbBinVersion?: number, schemaVersion?: number }>}
 */
export async function checkPendingMigration(projectDir) {
  const schemaVersion = await readSchemaVersion(projectDir);
  const dbBinPath = path.join(projectDir, "db.bin");

  try {
    const contents = await fs.promises.readFile(dbBinPath);
    const parsed = parseDbBinHeader(contents);
    if (parsed.schemaVersion < schemaVersion) {
      return {
        pending: true,
        dbBinVersion: parsed.schemaVersion,
        schemaVersion,
      };
    }
    return { pending: false };
  } catch (error) {
    if (error.code === "ENOENT") {
      return { pending: false };
    }
    throw error;
  }
}

// --- A3: createSnapshot ---

/**
 * Create a version snapshot and migration stub.
 * - Writes `.elm-pages-db/Db/V{currentVersion}.elm` (frozen snapshot)
 * - Writes `.elm-pages-db/Db/Migrate/V{currentVersion+1}.elm` (migration stub)
 * - Bumps schema-version.json to currentVersion + 1
 *
 * @param {string} projectDir - Project root directory
 * @param {string} dbSource - Current Db.elm source text
 * @param {number} currentVersion - Current schema version (the one being snapshotted)
 * @returns {Promise<void>}
 */
export async function createSnapshot(projectDir, dbSource, currentVersion) {
  const newVersion = currentVersion + 1;
  const dbDir = path.join(projectDir, ".elm-pages-db", "Db");
  const migrateDir = path.join(dbDir, "Migrate");

  // Create directories
  await fs.promises.mkdir(migrateDir, { recursive: true });

  // Write snapshot
  const snapshotSource = rewriteDbModuleToSnapshot(dbSource, currentVersion);
  await fs.promises.writeFile(
    path.join(dbDir, `V${currentVersion}.elm`),
    snapshotSource
  );

  // Write migration stub
  const stubSource = generateMigrationStub(currentVersion, newVersion);
  await fs.promises.writeFile(
    path.join(migrateDir, `V${newVersion}.elm`),
    stubSource
  );

  // Bump schema version
  await writeSchemaVersion(projectDir, newVersion);
}

// --- B1-B2: generateMigrateChain ---

/**
 * Generate the MigrateChain.elm source for applying a chain of migrations.
 *
 * For targetVersion=2 (V1→V2): reads V1 data, applies MigrateV2.migrate, writes new Db.
 * For targetVersion=3 (V1→V2→V3): reads V1 or V2 data, chains through all migrations.
 *
 * @param {number} targetVersion - The target schema version (>= 2)
 * @returns {string} Elm source for MigrateChain.elm
 */
export function generateMigrateChain(targetVersion) {
  // Versions we need snapshots for: 1..targetVersion-1
  const snapshotVersions = [];
  for (let v = 1; v < targetVersion; v++) {
    snapshotVersions.push(v);
  }

  // Generate imports
  const imports = [
    "import BackendTask exposing (BackendTask)",
    "import BackendTask.Http",
    "import Base64",
    "import Bytes exposing (Bytes)",
    "import Bytes.Decode",
    "import Bytes.Encode",
    "import Db",
    ...snapshotVersions.map((v) => `import Db.V${v}`),
    ...snapshotVersions.map(
      (v) => `import Db.Migrate.V${v + 1} as MigrateV${v + 1}`
    ),
    "import FatalError exposing (FatalError)",
    "import Json.Decode as Decode",
    "import Json.Encode as Encode",
    "import Lamdera.Wire3 as Wire",
    "import Pages.Script as Script exposing (Script)",
  ];

  // Generate case branches
  const caseBranches = snapshotVersions
    .map((v) => {
      return `                        ${v} ->
                            case Wire.bytesDecode Db.V${v}.w3_decode_Db bytes of
                                Just model ->
                                    migrateFromV${v} model

                                Nothing ->
                                    BackendTask.fail
                                        (FatalError.build
                                            { title = "Migration decode failed"
                                            , body = "Could not decode db.bin as V${v} data."
                                            }
                                        )`;
    })
    .join("\n\n");

  // Generate migrateFromV{n} functions
  // migrateFromV{last} applies MigrateV{last+1}.migrate then saves
  // migrateFromV{earlier} applies MigrateV{earlier+1}.migrate then chains to migrateFromV{earlier+1}
  const migrateFunctions = snapshotVersions
    .map((v) => {
      const isLast = v === targetVersion - 1;
      if (isLast) {
        return `
migrateFromV${v} : Db.V${v}.Db -> BackendTask FatalError ()
migrateFromV${v} model =
    saveAndLog (MigrateV${v + 1}.migrate model) ${v} ${targetVersion}`;
      } else {
        return `
migrateFromV${v} : Db.V${v}.Db -> BackendTask FatalError ()
migrateFromV${v} model =
    migrateFromV${v + 1} (MigrateV${v + 1}.migrate model)`;
      }
    })
    .join("\n");

  return `module MigrateChain exposing (run)

${imports.join("\n")}


run : Script
run =
    Script.withoutCliOptions
        (readDbBin
            |> BackendTask.andThen
                (\\{ version, bytes } ->
                    case version of
${caseBranches}

                        other ->
                            BackendTask.fail
                                (FatalError.build
                                    { title = "Unknown db.bin version"
                                    , body = "db.bin is at version " ++ String.fromInt other ++ " but I only know how to migrate from versions 1-${targetVersion - 1}."
                                    }
                                )
                )
        )

${migrateFunctions}


internalRequest : String -> BackendTask.Http.Body -> BackendTask.Http.Expect a -> BackendTask FatalError a
internalRequest name body expect =
    BackendTask.Http.request
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        expect
        |> BackendTask.allowFatal


saveAndLog : Db.Db -> Int -> Int -> BackendTask FatalError ()
saveAndLog newDb fromVersion toVersion =
    let
        wire3Bytes =
            Wire.bytesEncode (Db.w3_encode_Db newDb)

        base64Data =
            Base64.fromBytes wire3Bytes
                |> Maybe.withDefault ""
    in
    internalRequest "db-migrate-write"
        (BackendTask.Http.jsonBody
            (Encode.object
                [ ( "data", Encode.string base64Data )
                ]
            )
        )
        (BackendTask.Http.expectJson (Decode.succeed ()))


readDbBin : BackendTask FatalError { version : Int, bytes : Bytes }
readDbBin =
    internalRequest "db-migrate-read"
        (BackendTask.Http.jsonBody Encode.null)
        (BackendTask.Http.expectJson
            (Decode.map2 (\\v d -> { version = v, rawData = d })
                (Decode.field "version" Decode.int)
                (Decode.field "data" Decode.string)
            )
        )
        |> BackendTask.andThen
            (\\{ version, rawData } ->
                case Base64.toBytes rawData of
                    Just bytes ->
                        BackendTask.succeed { version = version, bytes = bytes }

                    Nothing ->
                        BackendTask.fail
                            (FatalError.build
                                { title = "Migration read failed"
                                , body = "Could not decode base64 data from db.bin."
                                }
                            )
            )
`;
}

// --- B3: writeMigrateChain ---

/**
 * Write MigrateChain.elm to .elm-pages-db/.
 * @param {string} projectDir - Project root directory
 * @param {number} targetVersion - The target schema version
 * @returns {Promise<void>}
 */
export async function writeMigrateChain(projectDir, targetVersion) {
  const dbDir = path.join(projectDir, ".elm-pages-db");
  await fs.promises.mkdir(dbDir, { recursive: true });
  const chainSource = generateMigrateChain(targetVersion);
  await fs.promises.writeFile(
    path.join(dbDir, "MigrateChain.elm"),
    chainSource
  );
}

// --- C1: detectMigrationNeeded ---

/**
 * Detect whether a migration is needed by comparing db.bin version vs schema version.
 * @param {string} projectDir - Project root directory
 * @returns {Promise<{ action: string, fromVersion?: number, toVersion?: number }>}
 */
export async function detectMigrationNeeded(projectDir) {
  const schemaVersion = await readSchemaVersion(projectDir);
  const dbBinPath = path.join(projectDir, "db.bin");

  try {
    const contents = await fs.promises.readFile(dbBinPath);
    const parsed = parseDbBinHeader(contents);

    if (parsed.schemaVersion === schemaVersion) {
      return { action: "up-to-date" };
    } else if (parsed.schemaVersion < schemaVersion) {
      return {
        action: "migrate",
        fromVersion: parsed.schemaVersion,
        toVersion: schemaVersion,
      };
    } else {
      return { action: "error" };
    }
  } catch (error) {
    if (error.code === "ENOENT") {
      return { action: "no-db" };
    }
    throw error;
  }
}

// --- C2: validateMigrationChain ---

/**
 * Validate that all required snapshot and migration files exist and are implemented.
 * @param {string} projectDir - Project root directory
 * @param {number} fromVersion - Starting schema version (in db.bin)
 * @param {number} toVersion - Target schema version
 * @returns {Promise<{ valid: boolean, missingFiles?: string[], unimplemented?: string[] }>}
 */
export async function validateMigrationChain(projectDir, fromVersion, toVersion) {
  const missingFiles = [];
  const unimplemented = [];
  const dbDir = path.join(projectDir, ".elm-pages-db");

  // Check snapshot files: V{i}.elm for i in [fromVersion..toVersion-1]
  for (let v = fromVersion; v < toVersion; v++) {
    const snapshotPath = path.join(dbDir, "Db", `V${v}.elm`);
    if (!fs.existsSync(snapshotPath)) {
      missingFiles.push(`Db/V${v}.elm`);
    }
  }

  // Check migration files: Migrate/V{i}.elm for i in [fromVersion+1..toVersion]
  for (let v = fromVersion + 1; v <= toVersion; v++) {
    const migrationPath = path.join(dbDir, "Db", "Migrate", `V${v}.elm`);
    if (!fs.existsSync(migrationPath)) {
      missingFiles.push(`Db/Migrate/V${v}.elm`);
    } else {
      // Check for sentinel
      const content = fs.readFileSync(migrationPath, "utf8");
      if (content.includes("todo_implement_migration")) {
        unimplemented.push(`Db/Migrate/V${v}.elm`);
      }
    }
  }

  if (missingFiles.length > 0 || unimplemented.length > 0) {
    return { valid: false, missingFiles, unimplemented };
  }
  return { valid: true };
}

// --- copyMigrationElmFiles ---

/**
 * Recursively copy .elm files from srcDir to destDir.
 * @param {string} srcDir - Source directory (e.g. .elm-pages-db)
 * @param {string} destDir - Destination directory (e.g. .elm-pages source dir)
 * @returns {string[]} List of copied file paths (for cleanup)
 */
export function copyMigrationElmFiles(srcDir, destDir) {
  const copiedFiles = [];
  function copyRecursive(src, dest) {
    if (!fs.existsSync(src)) return;
    for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        copyRecursive(path.join(src, entry.name), path.join(dest, entry.name));
      } else if (entry.name.endsWith(".elm")) {
        const destPath = path.join(dest, entry.name);
        fs.mkdirSync(dest, { recursive: true });
        fs.copyFileSync(path.join(src, entry.name), destPath);
        copiedFiles.push(destPath);
      }
    }
  }
  copyRecursive(srcDir, destDir);
  return copiedFiles;
}

// --- applyMigration ---

/**
 * Compile and run MigrateChain.elm standalone to apply a pending migration.
 * Bootstraps its own compilation environment.
 * @param {string} cwd - Current working directory (project root)
 * @param {number} fromVersion - Source schema version (in db.bin)
 * @param {number} toVersion - Target schema version
 * @returns {Promise<void>}
 */
export async function applyMigration(cwd, fromVersion, toVersion) {
  // Dynamic imports to avoid circular dependency (shared.js imports from db-migrate.js)
  const [
    { generatorWrapperFile, requireElm, lamderaOrElmFallback },
    { ensureDirSync, writeFileIfChanged, syncFilesToDirectory },
    { rewriteElmJson },
    globby,
    { compileCliApp },
    renderer,
  ] = await Promise.all([
    import("./commands/shared.js"),
    import("./file-helpers.js"),
    import("./rewrite-elm-json.js"),
    import("globby"),
    import("./compile-elm.js"),
    import("./render.js"),
  ]);

  // Find project directory
  const projectDirectory = findProjectDirectory(cwd);

  const compileDir = path.join(projectDirectory, "elm-stuff", "elm-pages");
  const elmPagesSourceDir = path.join(compileDir, ".elm-pages");

  ensureDirSync(path.join(projectDirectory, "elm-stuff"));
  ensureDirSync(elmPagesSourceDir);

  // Generate MigrateChain.elm
  await writeMigrateChain(cwd, toVersion);

  // Set up compilation environment (same steps as compileElmForScript)
  const executableName = await lamderaOrElmFallback();
  const elmFiles = globby.globbySync(`${projectDirectory}/*.elm`);
  await syncFilesToDirectory(
    elmFiles,
    `${projectDirectory}/elm-stuff/elm-pages/parentDirectory`,
    (file) => path.basename(file)
  );

  await rewriteElmJson(
    `${projectDirectory}/elm.json`,
    `${projectDirectory}/elm-stuff/elm-pages/elm.json`,
    { executableName }
  );

  // Copy migration files into compile source dir
  const migrationDbDir = path.join(cwd, ".elm-pages-db");
  const copiedFiles = copyMigrationElmFiles(migrationDbDir, elmPagesSourceDir);

  try {
    // Write ScriptMain wrapper for MigrateChain
    await writeFileIfChanged(
      path.join(elmPagesSourceDir, "ScriptMain.elm"),
      generatorWrapperFile("MigrateChain")
    );

    // Compile
    const elmEntrypointPath = path.join(elmPagesSourceDir, "ScriptMain.elm");
    const migrateOutputPath = path.join(compileDir, "migrate-chain.js");
    await compileCliApp(
      { debug: true },
      elmEntrypointPath,
      migrateOutputPath,
      compileDir,
      migrateOutputPath
    );

    // Run the migration
    const Elm = await requireElm(migrateOutputPath.replace(/\.js$/, ".cjs"));
    await renderer.runGenerator([], null, Elm, "MigrateChain");
  } finally {
    // Clean up copied migration files
    for (const filePath of copiedFiles) {
      try { fs.unlinkSync(filePath); } catch (_) {}
    }
    try { fs.rmdirSync(path.join(elmPagesSourceDir, "Db", "Migrate")); } catch (_) {}
    try { fs.rmdirSync(path.join(elmPagesSourceDir, "Db")); } catch (_) {}
  }
}

/**
 * Find the project directory (containing elm.json) from CWD.
 * Checks script/elm.json first, then elm.json in CWD.
 * @param {string} cwd
 * @returns {string}
 */
function findProjectDirectory(cwd) {
  const scriptElmJson = path.join(cwd, "script", "elm.json");
  if (fs.existsSync(scriptElmJson)) {
    return path.join(cwd, "script");
  }
  const rootElmJson = path.join(cwd, "elm.json");
  if (fs.existsSync(rootElmJson)) {
    return cwd;
  }
  throw new Error(
    "Could not find elm.json in current directory or script/ subdirectory."
  );
}

// --- C3: prepareMigrationSourceDirs ---

/**
 * Add .elm-pages-db to the compile directory's elm.json source-directories.
 * Returns a restore function that removes it.
 * @param {string} compileDir - The elm compilation directory
 * @param {string} projectDir - The project root directory
 * @returns {Promise<() => Promise<void>>} Restore function
 */
export async function prepareMigrationSourceDirs(compileDir, projectDir) {
  const elmJsonPath = path.join(compileDir, "elm.json");
  const original = await fs.promises.readFile(elmJsonPath, "utf8");
  const elmJson = JSON.parse(original);
  const originalSourceDirs = [...elmJson["source-directories"]];

  // Add path to .elm-pages-db relative to compile dir
  const migrationDir = path.relative(
    compileDir,
    path.join(projectDir, ".elm-pages-db")
  );
  elmJson["source-directories"].push(migrationDir);

  await fs.promises.writeFile(elmJsonPath, JSON.stringify(elmJson, null, 4));

  // Return restore function
  return async () => {
    const current = JSON.parse(
      await fs.promises.readFile(elmJsonPath, "utf8")
    );
    current["source-directories"] = originalSourceDirs;
    await fs.promises.writeFile(
      elmJsonPath,
      JSON.stringify(current, null, 4)
    );
  };
}
