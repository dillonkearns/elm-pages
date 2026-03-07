/**
 * Shared utilities for CLI commands.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";

// Cache for lamdera executable check
let lamderaVerified = false;

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
 * @param {{ suppressConsoleLog?: boolean }} [options]
 */
export async function requireElm(compiledElmPath, options = {}) {
  const warnOriginal = console.warn;
  const logOriginal = console.log;
  console.warn = function () {};
  if (options.suppressConsoleLog) {
    console.log = function () {};
  }

  try {
    let Elm = (
      await import(url.pathToFileURL(path.resolve(compiledElmPath)).href)
    ).default;
    return Elm;
  } finally {
    console.warn = warnOriginal;
    console.log = logOriginal;
  }
}

/**
 * Detect whether a reserved CLI flag is present before `--`.
 *
 * Flags after `--` are treated as positional arguments, which matches
 * standard CLI behavior and avoids false positives for explicit passthrough.
 *
 * @param {string[]} cliOptions
 * @param {string} flagName
 */
export function hasReservedCliFlag(cliOptions, flagName) {
  for (const cliOption of cliOptions) {
    if (cliOption === "--") {
      return false;
    }

    if (cliOption === flagName) {
      return true;
    }
  }

  return false;
}

/**
 * Generate a ScriptMain.elm that batch-introspects multiple scripts.
 * @param {Array<{moduleName: string, path: string}>} scripts
 */
export function introspectWrapperFile(scripts) {
  const imports = scripts.map((s) => `import ${s.moduleName}`).join("\n");

  const entries = scripts
    .map(
      (s) =>
        `                        Script.metadata { moduleName = "${s.moduleName}", path = "${s.path}" } ${s.moduleName}.run`
    )
    .join("\n                        , ");

  return `port module ScriptMain exposing (main)

import Bytes exposing (Bytes)
import Json.Decode
import Json.Encode
import Pages.Internal.Platform.GeneratorApplication
import Pages.Script as Script
${imports}


main : Pages.Internal.Platform.GeneratorApplication.Program
main =
    Pages.Internal.Platform.GeneratorApplication.app
        { data = introspectAll
        , scriptModuleName = "IntrospectAll"
        , toJsPort = toJsPort
        , fromJsPort = fromJsPort identity
        , gotBatchSub = gotBatchSub identity
        , sendPageData = \\_ -> Cmd.none
        }


introspectAll : Script.Script
introspectAll =
    Script.withoutCliOptions
        (Script.log
            (Json.Encode.encode 0
                (Json.Encode.list identity
                    (List.filterMap identity
                        [ ${entries}
                        ]
                    )
                )
            )
        )


port toJsPort : { json : Json.Encode.Value, bytes : List { key : String, data : Bytes } } -> Cmd msg


port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg


port gotBatchSub : (List { key : String, json : Json.Decode.Value, bytes : Maybe Bytes } -> msg) -> Sub msg
`;
}

/**
 * @param {string} moduleName
 */
export function generatorWrapperFile(moduleName) {
  return `port module ScriptMain exposing (main)

import Bytes exposing (Bytes)
import Json.Decode
import Json.Encode
import Pages.Internal.Platform.GeneratorApplication
import ${moduleName}


main : Pages.Internal.Platform.GeneratorApplication.Program
main =
    Pages.Internal.Platform.GeneratorApplication.app
        { data = ${moduleName}.run
        , scriptModuleName = "${moduleName}"
        , toJsPort = toJsPort
        , fromJsPort = fromJsPort identity
        , gotBatchSub = gotBatchSub identity
        , sendPageData = \\_ -> Cmd.none
        }


port toJsPort : { json : Json.Encode.Value, bytes : List { key : String, data : Bytes } } -> Cmd msg


port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg


port gotBatchSub : (List { key : String, json : Json.Decode.Value, bytes : Maybe Bytes } -> msg) -> Sub msg
`;
}

/**
 * Generate the Pages.Db Elm module source code.
 * @param {string} schemaHash - 64-character hex string of the Db.elm SHA-256 hash
 * @param {number} schemaVersion - Schema version derived from db/Db/Migrate/V*.elm files
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
    ? Array.from({ length: schemaVersion - 1 }, (_, index) => {
        const version = index + 2;
        return `import Db.Migrate.V${version} as MigrateV${version}`;
      })
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
                    persistMigrated connection (migrateFromV${fromVersion} oldDb)

                Nothing ->
                    BackendTask.fail
                        (FatalError.build
                            { title = "db.bin migration decode failed"
                            , body = "Could not decode db.bin as V${fromVersion} data."
                            }
                        )`;
      }).join("\n\n")
    : "";

  return `module Pages.Db exposing (Connection, default, open, get, update, transaction, testConfig)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Bytes exposing (Bytes)
import Bytes.Decode as BD
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


type Connection
    = Connection String


default : Connection
default =
    Connection ""


open : String -> Connection
open dbPath =
    Connection dbPath


connectionFields : Connection -> List ( String, Encode.Value )
connectionFields (Connection dbPath) =
    if dbPath == "" then
        []

    else
        [ ( "path", Encode.string dbPath ) ]


connectionHeaders : Connection -> List ( String, String )
connectionHeaders (Connection dbPath) =
    if dbPath == "" then
        []

    else
        [ ( "x-db-path", dbPath ) ]


type alias DbReadPayload =
    { version : Int
    , hash : String
    , data : Bytes
    }


dbReadPayloadBytesDecoder : BD.Decoder DbReadPayload
dbReadPayloadBytesDecoder =
    BD.unsignedInt32 Bytes.BE
        |> BD.andThen
            (\\version ->
                BD.bytes 32
                    |> BD.andThen
                        (\\hashBytes ->
                            BD.unsignedInt32 Bytes.BE
                                |> BD.andThen
                                    (\\wire3Len ->
                                        BD.bytes wire3Len
                                            |> BD.map
                                                (\\wire3 ->
                                                    { version = version
                                                    , hash = bytesToHexString hashBytes
                                                    , data = wire3
                                                    }
                                                )
                                    )
                        )
            )


bytesToHexString : Bytes -> String
bytesToHexString bytes =
    BD.decode (bytesToHexDecoder (Bytes.width bytes)) bytes
        |> Maybe.withDefault ""


bytesToHexDecoder : Int -> BD.Decoder String
bytesToHexDecoder len =
    bytesToHexHelp len []


bytesToHexHelp : Int -> List String -> BD.Decoder String
bytesToHexHelp remaining acc =
    if remaining <= 0 then
        BD.succeed (String.join "" (List.reverse acc))
    else
        BD.unsignedInt8
            |> BD.andThen
                (\\byte ->
                    bytesToHexHelp (remaining - 1) (byteToHex byte :: acc)
                )


byteToHex : Int -> String
byteToHex byte =
    let
        hi =
            byte // 16

        lo =
            modBy 16 byte
    in
    String.fromList [ hexDigit hi, hexDigit lo ]


hexDigit : Int -> Char
hexDigit n =
    case n of
        0 -> '0'
        1 -> '1'
        2 -> '2'
        3 -> '3'
        4 -> '4'
        5 -> '5'
        6 -> '6'
        7 -> '7'
        8 -> '8'
        9 -> '9'
        10 -> 'a'
        11 -> 'b'
        12 -> 'c'
        13 -> 'd'
        14 -> 'e'
        _ -> 'f'


internalRequest : String -> BackendTask.Http.Body -> BackendTask.Http.Expect a -> BackendTask FatalError a
internalRequest name body expect =
    internalRequestWithHeaders name [] body expect


internalRequestWithHeaders : String -> List ( String, String ) -> BackendTask.Http.Body -> BackendTask.Http.Expect a -> BackendTask FatalError a
internalRequestWithHeaders name headers body expect =
    BackendTask.Http.request
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = headers
        , body = body
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        expect
        |> BackendTask.allowFatal


get : Connection -> BackendTask FatalError Db.Db
get connection =
    loadDb connection


loadDb : Connection -> BackendTask FatalError Db.Db
loadDb connection =
    readPayload connection
        |> BackendTask.andThen (resolveReadPayload connection)


resolveReadPayload : Connection -> DbReadPayload -> BackendTask FatalError Db.Db
resolveReadPayload connection payload =
    if payload.version <= 0 || Bytes.width payload.data == 0 then
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

    else if payload.version == schemaVersion then
        decodeCurrent connection payload.hash payload.data

    else
        migrateFromVersion connection payload.version payload.data


decodeCurrent : Connection -> String -> Bytes -> BackendTask FatalError Db.Db
decodeCurrent connection storedHash bytes =
    case Wire.bytesDecode Db.w3_decode_Db bytes of
        Just db ->
            if storedHash == schemaHash then
                BackendTask.succeed db

            else
                persistMigrated connection db

        Nothing ->
            if storedHash == schemaHash then
                BackendTask.fail
                    (FatalError.build
                        { title = "db.bin decode failed"
                        , body = "Data is corrupted. Delete db.bin and its matching .lock file to start fresh."
                        }
                    )

            else
                BackendTask.fail
                    (FatalError.build
                        { title = "db.bin schema mismatch"
                        , body = "The stored data uses an incompatible schema. Run \`elm-pages db migrate\` and implement migrations, or reset the database."
                        }
                    )


migrateFromVersion : Connection -> Int -> Bytes -> BackendTask FatalError Db.Db
migrateFromVersion connection version bytes =
    case version of
${hasMigrations ? migrationBranches : ""}

        _ ->
            BackendTask.fail
                (FatalError.build
                    { title = "db.bin migration failed"
                    , body = "No migration path exists from V" ++ String.fromInt version ++ " to V" ++ String.fromInt schemaVersion ++ "."
                    }
                )


readPayload : Connection -> BackendTask FatalError DbReadPayload
readPayload connection =
    internalRequest "db-read-meta"
        (BackendTask.Http.jsonBody (Encode.object (connectionFields connection)))
        (BackendTask.Http.expectBytes dbReadPayloadBytesDecoder)


persistMigrated : Connection -> Db.Db -> BackendTask FatalError Db.Db
persistMigrated connection db =
    let
        wire3Bytes =
            Wire.bytesEncode (Db.w3_encode_Db db)
    in
    internalRequestWithHeaders "db-migrate-write"
        (connectionHeaders connection)
        (BackendTask.Http.bytesBody "application/octet-stream" wire3Bytes)
        (BackendTask.Http.expectJson (Decode.succeed ()))
        |> BackendTask.map (\\_ -> db)


${migrateFunctions}


update : Connection -> (Db.Db -> Db.Db) -> BackendTask FatalError ()
update connection fn =
    transaction connection (\\db -> BackendTask.succeed ( fn db, () ))


transaction : Connection -> (Db.Db -> BackendTask FatalError ( Db.Db, a )) -> BackendTask FatalError a
transaction connection fn =
    acquireLock connection
        |> BackendTask.andThen
            (\\token ->
                get connection
                    |> BackendTask.andThen (\\db -> fn db)
                    |> BackendTask.andThen
                        (\\( newDb, result ) ->
                            write connection newDb
                                |> BackendTask.map (\\_ -> result)
                        )
                    |> BackendTask.toResult
                    |> BackendTask.andThen
                        (\\result ->
                            releaseLock connection token
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


write : Connection -> Db.Db -> BackendTask FatalError ()
write connection db =
    let
        wire3Bytes =
            Wire.bytesEncode (Db.w3_encode_Db db)
    in
    internalRequestWithHeaders "db-write"
        (( "x-schema-hash", schemaHash ) :: connectionHeaders connection)
        (BackendTask.Http.bytesBody "application/octet-stream" wire3Bytes)
        (BackendTask.Http.expectJson (Decode.succeed ()))


acquireLock : Connection -> BackendTask FatalError String
acquireLock connection =
    internalRequest "db-lock-acquire"
        (BackendTask.Http.jsonBody (Encode.object (connectionFields connection)))
        (BackendTask.Http.expectJson Decode.string)


releaseLock : Connection -> String -> BackendTask FatalError ()
releaseLock connection token =
    internalRequest "db-lock-release"
        (BackendTask.Http.jsonBody
            (Encode.object
                ([ ( "token", Encode.string token ) ]
                    ++ connectionFields connection
                )
            )
        )
        (BackendTask.Http.expectJson (Decode.succeed ()))


testConfig :
    { schemaVersion : Int
    , schemaHash : String
    , encode : Db.Db -> Bytes
    , decode : Bytes -> Maybe Db.Db
    , seed : Db.Db
    }
testConfig =
    { schemaVersion = schemaVersion
    , schemaHash = schemaHash
    , encode = \\db -> Wire.bytesEncode (Db.w3_encode_Db db)
    , decode = \\bytes -> Wire.bytesDecode Db.w3_decode_Db bytes
    , seed = Pages.DbSeed.seedCurrent
    }
`;
}

/**
 * Generate the Pages.DbSeed module source code.
 * Always seeds from `Db.Migrate.V1.seed ()` through the migration chain.
 *
 * @param {number} schemaVersion
 * @returns {string}
 */
export function generatePagesDbSeedModule(schemaVersion) {
  const imports = [
    "import Db",
    "import Db.Migrate.V1 as MigrateV1",
    ...Array.from({ length: Math.max(0, schemaVersion - 1) }, (_, index) => {
      const version = index + 2;
      return `import Db.Migrate.V${version} as MigrateV${version}`;
    }),
  ];

  const pipeline = Array.from(
    { length: Math.max(0, schemaVersion - 1) },
    (_, index) => {
      const version = index + 2;
      return `|> MigrateV${version}.seed`;
    }
  ).join("\n        ");

  const seedExpr = pipeline
    ? `MigrateV1.seed ()\n        ${pipeline}`
    : `MigrateV1.seed ()`;

  return `module Pages.DbSeed exposing (seedCurrent)

${imports.join("\n")}


seedCurrent : Db.Db
seedCurrent =
    ${seedExpr}
`;
}

export async function requireLamdera() {
  if (lamderaVerified) {
    return "lamdera";
  }
  const { default: which } = await import("which");
  try {
    await which("lamdera");
    lamderaVerified = true;
  } catch (error) {
    throw new Error(
      "I couldn't find lamdera on the PATH. elm-pages requires the lamdera compiler.\nhttps://lamdera.com"
    );
  }
  return "lamdera";
}

export async function compileElmForScript(
  elmModulePath,
  resolved,
  options = {}
) {
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
        console.error(
          `Warning: ${result.message}. This may cause stale generated code or missing module errors.\n`
        );
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
  const executableName = await requireLamdera();
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
    {}
  );

  // Generate Pages.Db module if this script uses the database.
  // This runs AFTER rewriteElmJson so generated modules are available for compile.
  if (options.usesDb) {
    const { computeSchemaHash, readSchemaVersion, saveSchemaSourceFromFile } =
      await import("../db-schema.js");
    const { validateMigrationChain, copyMigrationElmFiles } =
      await import("../db-migrate.js");

    // db.bin and db live at the runtime CWD (where the user runs
    // `elm-pages run`), NOT at projectDirectory.
    const runtimeDir = process.cwd();

    const dbElmPath = await findDbElm(projectDirectory, sourceDirectory);
    const schemaHash = await computeSchemaHash(dbElmPath);
    try {
      await saveSchemaSourceFromFile(runtimeDir, dbElmPath, schemaHash);
    } catch (_) {
      // Non-fatal: stale snapshot recovery won't be available without provenance.
    }

    const schemaVersion = await readSchemaVersion(runtimeDir);

    const compileDbDir = path.join(
      projectDirectory,
      "elm-stuff",
      "elm-pages",
      ".elm-pages",
      "Db"
    );
    // Validate the full seed chain (V0 → current) so fresh installs are
    // deterministic and safe. V0 is virtual (`()`), so validation starts from 0.
    const seedValidation = await validateMigrationChain(
      runtimeDir,
      0,
      schemaVersion
    );
    if (!seedValidation.valid) {
      const issues = [];
      if (
        seedValidation.missingFiles &&
        seedValidation.missingFiles.length > 0
      ) {
        issues.push(`Missing files: ${seedValidation.missingFiles.join(", ")}`);
      }
      if (
        seedValidation.unimplemented &&
        seedValidation.unimplemented.length > 0
      ) {
        issues.push(
          `Unimplemented migrations: ${seedValidation.unimplemented.join(", ")}`
        );
      }
      throw `Initial seed is incomplete for schema V${schemaVersion}.\n\nI need a valid seed chain so a fresh install (no db.bin) can initialize safely.\n\n${issues.join("\n")}\n\nImplement the migration stubs in db/Db/Migrate/ and rerun your script.`;
    }

    try {
      fs.rmSync(compileDbDir, { recursive: true, force: true });
    } catch (_) {}
    copyMigrationElmFiles(path.join(runtimeDir, "db", "Db"), compileDbDir);

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

Run \`elm-pages db init\` to create Db.elm and the V1 seed migration, or
create a file at ${dbElmInSource} with this template:

    module Db exposing (Db)

    type alias Db =
        { counter : Int
        }

The Db type alias defines the shape of your database. The V1 seed in
db/Db/Migrate/V1.elm provides the initial value used when
no db.bin file exists yet.`;
}

/**
 * Check if an Elm module exposes a given value name.
 * @param {string} filePath - Path to the .elm file
 * @param {string} valueName - The name to look for in the exposing list
 * @returns {boolean}
 */
export function moduleExposesValue(filePath, valueName) {
  try {
    const content = fs.readFileSync(filePath, "utf8");
    const match = content.match(/^module\s+\S+\s+exposing\s*\(([\s\S]*?)\)/m);
    if (!match) return false;
    const exposing = match[1];
    if (exposing.trim() === "..") return moduleDefinesValue(content, valueName);
    const pattern = new RegExp(`(?:^|[,\\s])${valueName}(?:$|[,\\s])`);
    return pattern.test(exposing);
  } catch (_) {
    return false;
  }
}

function moduleDefinesValue(content, valueName) {
  const annotationPattern = new RegExp(`^${valueName}\\s*:`, "m");
  const definitionPattern = new RegExp(`^${valueName}(?:\\s|=)`, "m");
  return annotationPattern.test(content) || definitionPattern.test(content);
}
