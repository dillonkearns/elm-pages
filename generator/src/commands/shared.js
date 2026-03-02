/**
 * Shared utilities for CLI commands.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";

// Cache for lamdera/elm executable name to avoid repeated which() calls
let cachedExecutableName = null;

/**
 * @param {string} rawPagePath
 */
export function normalizeUrl(rawPagePath) {
  const segments = rawPagePath
    .split("/")
    // Filter out all empty segments.
    .filter((segment) => segment.length != 0);

  // Do not add a trailing slash.
  // The core issue is that `/base` is a prefix of `/base/`, but
  // `/base/` is not a prefix of `/base`, which can later lead to issues
  // with detecting whether the path contains the base.
  return `/${segments.join("/")}`;
}

/**
 * @param {Error|string|any[]} error - Thing that was thrown and caught.
 * @param {Function} [restoreColorSafe] - Optional color restore function.
 */
export function printCaughtError(error, restoreColorSafe) {
  if (typeof error === "string" || Array.isArray(error)) {
    if (restoreColorSafe) {
      console.log(restoreColorSafe(error));
    } else {
      console.log(error);
    }
  } else if (error instanceof Error) {
    console.error(error.message);
  } else {
    console.trace(error);
  }
}

/**
 * @param {string} compiledElmPath
 */
export async function requireElm(compiledElmPath) {
  const warnOriginal = console.warn;
  console.warn = function () {};

  let Elm = (
    await import(url.pathToFileURL(path.resolve(compiledElmPath)).href)
  ).default;
  console.warn = warnOriginal;
  return Elm;
}

/**
 * @param {string} moduleName
 */
export function generatorWrapperFile(moduleName) {
  return `port module ScriptMain exposing (main)

import Pages.Internal.Platform.GeneratorApplication
import ${moduleName}


main : Pages.Internal.Platform.GeneratorApplication.Program
main =
    Pages.Internal.Platform.GeneratorApplication.app
        { data = ${moduleName}.run
        , toJsPort = toJsPort
        , fromJsPort = fromJsPort identity
        , gotBatchSub = gotBatchSub identity
        , sendPageData = \\_ -> Cmd.none
        }


port toJsPort : Pages.Internal.Platform.GeneratorApplication.JsonValue -> Cmd msg


port fromJsPort : (Pages.Internal.Platform.GeneratorApplication.JsonValue -> msg) -> Sub msg


port gotBatchSub : (Pages.Internal.Platform.GeneratorApplication.JsonValue -> msg) -> Sub msg
`;
}

/**
 * Generate the Pages.Db Elm module source code.
 * @param {string} schemaHash - 64-character hex string of the Db.elm SHA-256 hash
 * @param {number} schemaVersion - Schema version from .elm-pages-db/schema-version.json
 * @returns {string} Elm source code for the Pages.Db module
 */
export function generatePagesDbModule(schemaHash, schemaVersion) {
  const hasMigrations = schemaVersion > 1;
  const snapshotImports = hasMigrations
    ? Array.from(
        { length: schemaVersion - 1 },
        (_, index) => `import Db.V${index + 1}`
      )
    : [];
  const migrationImports = hasMigrations
    ? Array.from(
        { length: schemaVersion - 1 },
        (_, index) => {
          const version = index + 2;
          return `import Db.Migrate.V${version} as MigrateV${version}`;
        }
      )
    : [];

  const migrateFunctions = hasMigrations
    ? Array.from({ length: schemaVersion - 1 }, (_, index) => {
        const fromVersion = index + 1;
        const migrateSteps = Array.from(
          { length: schemaVersion - fromVersion },
          (_, stepIndex) => {
            const version = fromVersion + stepIndex + 1;
            return `|> MigrateV${version}.migrate`;
          }
        ).join("\n        ");

        return `
migrateFromV${fromVersion} : Db.V${fromVersion}.Db -> Db.Db
migrateFromV${fromVersion} old =
    old
        ${migrateSteps}
`;
      }).join("\n")
    : "";

  const migrationBranches = hasMigrations
    ? Array.from({ length: schemaVersion - 1 }, (_, index) => {
        const fromVersion = index + 1;
        return `        ${fromVersion} ->
            case Wire.bytesDecode Db.V${fromVersion}.w3_decode_Db bytes of
                Just oldDb ->
                    persistMigrated (migrateFromV${fromVersion} oldDb)

                Nothing ->
                    BackendTask.fail
                        (FatalError.build
                            { title = "db.bin migration decode failed"
                            , body = "Could not decode db.bin as V${fromVersion} data."
                            }
                        )`;
      }).join("\n\n")
    : "";

  return `module Pages.Db exposing (get, update, transaction)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Base64
import Bytes exposing (Bytes)
import Db
${snapshotImports.join("\n")}
${migrationImports.join("\n")}
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Lamdera.Wire3 as Wire
import Pages.DbSeed


schemaHash : String
schemaHash =
    "${schemaHash}"


schemaVersion : Int
schemaVersion =
    ${schemaVersion}


type alias DbReadPayload =
    { version : Int
    , hash : String
    , data : String
    }


dbReadPayloadDecoder : Decode.Decoder DbReadPayload
dbReadPayloadDecoder =
    Decode.map3
        (\\version hash data ->
            { version = version
            , hash = hash
            , data = data
            }
        )
        (Decode.field "version" Decode.int)
        (Decode.field "hash" Decode.string)
        (Decode.field "data" Decode.string)


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


get : BackendTask FatalError Db.Db
get =
    loadDb


loadDb : BackendTask FatalError Db.Db
loadDb =
    readPayload
        |> BackendTask.andThen resolveReadPayload


resolveReadPayload : DbReadPayload -> BackendTask FatalError Db.Db
resolveReadPayload payload =
    if payload.version <= 0 || payload.data == "" then
        BackendTask.succeed Pages.DbSeed.seedCurrent

    else if payload.version > schemaVersion then
        BackendTask.fail
            (FatalError.build
                { title = "db.bin version is newer"
                , body =
                    "This script understands schema versions up to V"
                        ++ String.fromInt schemaVersion
                        ++ ", but db.bin is V"
                        ++ String.fromInt payload.version
                        ++ "."
                }
            )

    else
        case Base64.toBytes payload.data of
            Nothing ->
                BackendTask.fail
                    (FatalError.build
                        { title = "db.bin read failed"
                        , body = "Could not decode base64 data from db.bin."
                        }
                    )

            Just bytes ->
                if payload.version == schemaVersion then
                    decodeCurrent payload.hash bytes

                else
                    migrateFromVersion payload.version bytes


decodeCurrent : String -> Bytes -> BackendTask FatalError Db.Db
decodeCurrent storedHash bytes =
    case Wire.bytesDecode Db.w3_decode_Db bytes of
        Just db ->
            if storedHash == schemaHash then
                BackendTask.succeed db

            else
                persistMigrated db

        Nothing ->
            if storedHash == schemaHash then
                BackendTask.fail
                    (FatalError.build
                        { title = "db.bin decode failed"
                        , body = "Data is corrupted. Run \`elm-pages db reset\`."
                        }
                    )

            else
                BackendTask.fail
                    (FatalError.build
                        { title = "db.bin schema mismatch"
                        , body = "The stored data uses an incompatible schema. Run \`elm-pages db migrate\` and implement migrations, or reset the database."
                        }
                    )


migrateFromVersion : Int -> Bytes -> BackendTask FatalError Db.Db
migrateFromVersion version bytes =
    case version of
${hasMigrations ? migrationBranches : ""}

        _ ->
            BackendTask.fail
                (FatalError.build
                    { title = "db.bin migration failed"
                    , body = "No migration path exists from V" ++ String.fromInt version ++ " to V" ++ String.fromInt schemaVersion ++ "."
                    }
                )


readPayload : BackendTask FatalError DbReadPayload
readPayload =
    internalRequest "db-read-meta"
        (BackendTask.Http.jsonBody Encode.null)
        (BackendTask.Http.expectJson dbReadPayloadDecoder)


persistMigrated : Db.Db -> BackendTask FatalError Db.Db
persistMigrated db =
    let
        wire3Bytes =
            Wire.bytesEncode (Db.w3_encode_Db db)

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
        |> BackendTask.map (\\_ -> db)


${migrateFunctions}


update : (Db.Db -> Db.Db) -> BackendTask FatalError ()
update fn =
    transaction (\\db -> BackendTask.succeed ( fn db, () ))


transaction : (Db.Db -> BackendTask FatalError ( Db.Db, a )) -> BackendTask FatalError a
transaction fn =
    acquireLock
        |> BackendTask.andThen
            (\\token ->
                get
                    |> BackendTask.andThen (\\db -> fn db)
                    |> BackendTask.andThen
                        (\\( newDb, result ) ->
                            write newDb
                                |> BackendTask.map (\\_ -> result)
                        )
                    |> BackendTask.toResult
                    |> BackendTask.andThen
                        (\\result ->
                            releaseLock token
                                |> BackendTask.andThen
                                    (\\_ ->
                                        case result of
                                            Ok value ->
                                                BackendTask.succeed value

                                            Err error ->
                                                BackendTask.fail error
                                    )
                        )
            )


write : Db.Db -> BackendTask FatalError ()
write db =
    let
        wire3Bytes =
            Wire.bytesEncode (Db.w3_encode_Db db)

        base64Data =
            Base64.fromBytes wire3Bytes
                |> Maybe.withDefault ""
    in
    internalRequest "db-write"
        (BackendTask.Http.jsonBody
            (Encode.object
                [ ( "hash", Encode.string schemaHash )
                , ( "data", Encode.string base64Data )
                ]
            )
        )
        (BackendTask.Http.expectJson (Decode.succeed ()))


acquireLock : BackendTask FatalError String
acquireLock =
    internalRequest "db-lock-acquire"
        (BackendTask.Http.jsonBody Encode.null)
        (BackendTask.Http.expectJson Decode.string)


releaseLock : String -> BackendTask FatalError ()
releaseLock token =
    internalRequest "db-lock-release"
        (BackendTask.Http.jsonBody (Encode.string token))
        (BackendTask.Http.expectJson (Decode.succeed ()))
`;
}

/**
 * Generate the Pages.DbSeed module source code.
 * Uses Db.init for schema V1, and for V2+ bootstraps from Db.V1.init through
 * `seed` functions in each migration module.
 *
 * @param {number} schemaVersion
 * @returns {string}
 */
export function generatePagesDbSeedModule(schemaVersion) {
  if (schemaVersion <= 1) {
    return `module Pages.DbSeed exposing (seedCurrent)

import Db


seedCurrent : Db.Db
seedCurrent =
    Db.init
`;
  }

  const imports = [
    "import Db",
    "import Db.V1",
    ...Array.from(
      { length: schemaVersion - 1 },
      (_, index) => {
        const version = index + 2;
        return `import Db.Migrate.V${version} as MigrateV${version}`;
      }
    ),
  ];

  const pipeline = Array.from(
    { length: schemaVersion - 1 },
    (_, index) => {
      const version = index + 2;
      return `|> MigrateV${version}.seed`;
    }
  )
    .join("\n        ");

  return `module Pages.DbSeed exposing (seedCurrent)

${imports.join("\n")}


seedCurrent : Db.Db
seedCurrent =
    Db.V1.init
        ${pipeline}
`;
}

export async function lamderaOrElmFallback() {
  // Return cached result if available
  if (cachedExecutableName) {
    return cachedExecutableName;
  }
  const { default: which } = await import("which");
  try {
    await which("lamdera");
    cachedExecutableName = "lamdera";
  } catch (error) {
    try {
      await which("elm");
      cachedExecutableName = "elm";
    } catch (elmError) {
      throw new Error(
        "I couldn't find lamdera or elm on the PATH. Please ensure one of them is installed and available.\nhttps://lamdera.com\nhttps://guide.elm-lang.org/install/elm.html"
      );
    }
  }
  return cachedExecutableName;
}

export async function compileElmForScript(elmModulePath, resolved, options = {}) {
  const [
    { ensureDirSync, writeFileIfChanged, syncFilesToDirectory },
    { needsCodegenInstall, updateCodegenMarker },
    { runElmCodegenInstall },
    globby,
    { rewriteElmJson },
  ] = await Promise.all([
    import("../file-helpers.js"),
    import("../script-cache.js"),
    import("../elm-codegen.js"),
    import("globby"),
    import("../rewrite-elm-json.js"),
  ]);

  const { moduleName, projectDirectory, sourceDirectory } = resolved;
  const splitModuleName = moduleName.split(".");
  const expectedFilePath = path.join(
    sourceDirectory,
    `${splitModuleName.join("/")}.elm`
  );
  if (!fs.existsSync(expectedFilePath)) {
    throw `I couldn't find a module named ${expectedFilePath}`;
  }
  ensureDirSync(path.join(process.cwd(), ".elm-pages", "http-response-cache"));
  if (fs.existsSync("./codegen/") && process.env.SKIP_ELM_CODEGEN !== "true") {
    const shouldRunCodegen = await needsCodegenInstall(projectDirectory);
    if (shouldRunCodegen) {
      const result = await runElmCodegenInstall();
      if (!result.success) {
        console.error(`Warning: ${result.message}. This may cause stale generated code or missing module errors.\n`);
        if (result.error) {
          console.error(result.error);
        }
      } else {
        await updateCodegenMarker(projectDirectory);
      }
    }
  }

  ensureDirSync(`${projectDirectory}/elm-stuff`);
  ensureDirSync(`${projectDirectory}/elm-stuff/elm-pages/.elm-pages`);

  await writeFileIfChanged(
    path.join(
      `${projectDirectory}/elm-stuff/elm-pages/.elm-pages/ScriptMain.elm`
    ),
    generatorWrapperFile(moduleName)
  );
  const executableName = await lamderaOrElmFallback();
  // Copy .elm files from project root to parentDirectory, preserving mtimes
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

  // Generate Pages.Db module if this script uses the database.
  // This runs AFTER rewriteElmJson so generated modules are available for compile.
  if (options.usesDb) {
    const {
      computeSchemaHash, readSchemaVersion, writeSchemaVersion,
      saveSchemaSourceFromFile,
    } = await import("../db-schema.js");
    const { validateMigrationChain, copyMigrationElmFiles } = await import("../db-migrate.js");

    // db.bin and .elm-pages-db live at the runtime CWD (where the user runs
    // `elm-pages run`), NOT at projectDirectory.
    const runtimeDir = process.cwd();

    const dbElmPath = await findDbElm(projectDirectory, sourceDirectory);
    const schemaHash = await computeSchemaHash(dbElmPath);
    try {
      await saveSchemaSourceFromFile(runtimeDir, dbElmPath, schemaHash);
    } catch (_) {
      // Non-fatal: stale snapshot recovery won't be available without provenance.
    }

    // Ensure schema version file exists
    const schemaVersion = await readSchemaVersion(runtimeDir);
    await writeSchemaVersion(runtimeDir, schemaVersion);

    const compileDbDir = path.join(
      projectDirectory,
      "elm-stuff",
      "elm-pages",
      ".elm-pages",
      "Db"
    );
    if (schemaVersion > 1) {
      // Seeding from scratch at V2+ replays V1 -> current using migration functions.
      // Validate the full chain so fresh installs are deterministic and safe.
      const seedValidation = await validateMigrationChain(
        runtimeDir,
        1,
        schemaVersion
      );
      if (!seedValidation.valid) {
        const issues = [];
        if (seedValidation.missingFiles && seedValidation.missingFiles.length > 0) {
          issues.push(`Missing files: ${seedValidation.missingFiles.join(", ")}`);
        }
        if (seedValidation.unimplemented && seedValidation.unimplemented.length > 0) {
          issues.push(`Unimplemented migrations: ${seedValidation.unimplemented.join(", ")}`);
        }
        throw `Initial seed is incomplete for schema V${schemaVersion}.\n\nI need a valid V1 -> V${schemaVersion} migration chain so a fresh install (no db.bin) can initialize safely.\n\n${issues.join("\n")}\n\nImplement the migration stubs in .elm-pages-db/Db/Migrate/ and rerun your script.`;
      }

      try {
        fs.rmSync(compileDbDir, { recursive: true, force: true });
      } catch (_) {}
      copyMigrationElmFiles(
        path.join(runtimeDir, ".elm-pages-db", "Db"),
        compileDbDir
      );
    } else {
      try {
        fs.rmSync(compileDbDir, { recursive: true, force: true });
      } catch (_) {}
    }

    ensureDirSync(`${projectDirectory}/elm-stuff/elm-pages/.elm-pages/Pages`);
    await writeFileIfChanged(
      path.join(
        `${projectDirectory}/elm-stuff/elm-pages/.elm-pages/Pages/DbSeed.elm`
      ),
      generatePagesDbSeedModule(schemaVersion)
    );
    await writeFileIfChanged(
      path.join(
        `${projectDirectory}/elm-stuff/elm-pages/.elm-pages/Pages/Db.elm`
      ),
      generatePagesDbModule(schemaHash, schemaVersion)
    );
  }
}

/**
 * Find Db.elm in the project's source directories.
 * @param {string} projectDirectory
 * @param {string} sourceDirectory - The source directory where the script module was found
 * @returns {Promise<string>} Absolute path to Db.elm
 * @throws If Db.elm is not found
 */
async function findDbElm(projectDirectory, sourceDirectory) {
  // First check the script's own source directory
  const dbElmInSource = path.join(sourceDirectory, "Db.elm");
  if (fs.existsSync(dbElmInSource)) {
    return dbElmInSource;
  }

  // Also check all source directories from elm.json
  const elmJsonPath = path.join(projectDirectory, "elm.json");
  if (fs.existsSync(elmJsonPath)) {
    const elmJson = JSON.parse(await fs.promises.readFile(elmJsonPath, "utf8"));
    const sourceDirs = elmJson["source-directories"] || [];
    for (const dir of sourceDirs) {
      const candidate = path.resolve(projectDirectory, dir, "Db.elm");
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }
  }

  throw `Missing Db module

Your script imports Pages.Db, but I couldn't find a Db.elm module in your source directories.

Create a file at ${dbElmInSource} with this template:

    module Db exposing (Db, init)

    type alias Db =
        { counter : Int
        }

    init : Db
    init =
        { counter = 0
        }

The Db type alias defines the shape of your database, and init provides
the initial value used when no db.bin file exists yet.

After you create your first migration (V1 -> V2), new installs seed from
Db.V1.init through the migration chain, so Db.init is no longer required in
the current Db module.`;
}
