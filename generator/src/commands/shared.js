/**
 * Shared utilities for CLI commands.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";
import { createRequire } from "node:module";
import * as globby from "globby";

const requireCJS = createRequire(import.meta.url);
const elmTestParser = requireCJS("../vendor/elm-test-parser.cjs");

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
 * Generate a ScriptMain.elm that runs named TUI tests through the
 * interactive terminal stepper.
 * @param {string} moduleName
 * @param {string[]} tuiTestValues - names of exposed `Test.Tui.Test` values
 */
export function testStepperWrapperFile(moduleName, tuiTestValues) {
  const shouldPrefixExportName = tuiTestValues.length > 1;
  const snapshotEntries = tuiTestValues
    .map(
      (name) =>
        shouldPrefixExportName
          ? `            ${moduleName}.${name}\n` +
            `                |> Test.Tui.toNamedSnapshots\n` +
            `                |> List.map (\\( testName, snapshots ) -> ( "${name}: " ++ testName, snapshots ))`
          : `            Test.Tui.toNamedSnapshots ${moduleName}.${name}`
    )
    .join("\n            , ");

  return `port module ScriptMain exposing (main)

import Ansi.Color
import BackendTask
import Bytes exposing (Bytes)
import Json.Decode
import Json.Encode
import Pages.Internal.Platform.GeneratorApplication
import Pages.Script as Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Screen as Screen
import Tui.Sub
import Test.Tui
import ${moduleName}


main : Pages.Internal.Platform.GeneratorApplication.Program
main =
    Pages.Internal.Platform.GeneratorApplication.app
        { data =
            runNamed
                (List.concat
                    [ ${snapshotEntries}
                    ]
                )
        , scriptModuleName = "${moduleName}.Stepper"
        , toJsPort = toJsPort
        , fromJsPort = fromJsPort identity
        , gotBatchSub = gotBatchSub identity
        , sendPageData = \\_ -> Cmd.none
        }


runNamed : List ( String, List Test.Tui.Snapshot ) -> Script
runNamed namedTests =
    let
        allTests : List { name : String, snapshots : List Test.Tui.Snapshot }
        allTests =
            namedTests
                |> List.map (\\( name, snapshots ) -> { name = name, snapshots = snapshots })
    in
    Tui.program
        { data = BackendTask.succeed allTests
        , init = namedStepperInit
        , update = stepperUpdate
        , view = stepperView
        , subscriptions = stepperSubscriptions
        }
        |> Tui.toScript


type alias StepperModel =
    { snapshots : List Test.Tui.Snapshot
    , currentIndex : Int
    , allTests : List { name : String, snapshots : List Test.Tui.Snapshot }
    , currentTestIndex : Int
    }


type StepperMsg
    = KeyPressed Tui.Sub.KeyEvent


namedStepperInit : List { name : String, snapshots : List Test.Tui.Snapshot } -> ( StepperModel, Effect.Effect StepperMsg )
namedStepperInit tests =
    let
        firstSnapshots : List Test.Tui.Snapshot
        firstSnapshots =
            tests
                |> List.head
                |> Maybe.map .snapshots
                |> Maybe.withDefault []
    in
    ( { snapshots = firstSnapshots
      , currentIndex = 0
      , allTests = tests
      , currentTestIndex = 0
      }
    , Effect.none
    )


stepperUpdate : StepperMsg -> StepperModel -> ( StepperModel, Effect.Effect StepperMsg )
stepperUpdate msg model =
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Sub.Arrow Tui.Sub.Right ->
                    ( { model
                        | currentIndex =
                            min (List.length model.snapshots - 1) (model.currentIndex + 1)
                      }
                    , Effect.none
                    )

                Tui.Sub.Arrow Tui.Sub.Left ->
                    ( { model
                        | currentIndex = max 0 (model.currentIndex - 1)
                      }
                    , Effect.none
                    )

                Tui.Sub.Tab ->
                    switchToNextTest model

                Tui.Sub.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Sub.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )


switchToNextTest : StepperModel -> ( StepperModel, Effect.Effect StepperMsg )
switchToNextTest model =
    if List.length model.allTests <= 1 then
        ( model, Effect.none )

    else
        let
            nextIndex : Int
            nextIndex =
                modBy (List.length model.allTests) (model.currentTestIndex + 1)

            nextSnapshots : List Test.Tui.Snapshot
            nextSnapshots =
                model.allTests
                    |> List.drop nextIndex
                    |> List.head
                    |> Maybe.map .snapshots
                    |> Maybe.withDefault []
        in
        ( { model
            | currentTestIndex = nextIndex
            , snapshots = nextSnapshots
            , currentIndex = 0
          }
        , Effect.none
        )


stepperView : Tui.Context -> StepperModel -> Screen.Screen
stepperView ctx model =
    let
        dimStyling : Screen.Screen -> Screen.Screen
        dimStyling =
            Screen.dim

        maybeSnapshot : Maybe Test.Tui.Snapshot
        maybeSnapshot =
            model.snapshots
                |> List.drop model.currentIndex
                |> List.head
    in
    case maybeSnapshot of
        Just snapshot ->
            let
                headerStyling : Screen.Screen -> Screen.Screen
                headerStyling =
                    Screen.fg Ansi.Color.cyan >> Screen.bold

                separator : String
                separator =
                    String.repeat (ctx.width - 4) "─"

                headerText : String
                headerText =
                    if List.length model.allTests > 1 then
                        let
                            testName : String
                            testName =
                                model.allTests
                                    |> List.drop model.currentTestIndex
                                    |> List.head
                                    |> Maybe.map .name
                                    |> Maybe.withDefault "test"
                        in
                        "  " ++ testName ++ " — Step " ++ String.fromInt (model.currentIndex + 1) ++ " of " ++ String.fromInt (List.length model.snapshots)

                    else
                        "  Test Stepper — Step " ++ String.fromInt (model.currentIndex + 1) ++ " of " ++ String.fromInt (List.length model.snapshots)

                footerText : String
                footerText =
                    if List.length model.allTests > 1 then
                        "  ← → navigate   Tab next test   q quit"

                    else
                        "  ← → navigate   q quit"

                stepIndicator : Screen.Screen
                stepIndicator =
                    Screen.concat
                        (model.snapshots
                            |> List.indexedMap
                                (\\i snapshotForIndicator ->
                                    if i == model.currentIndex then
                                        Screen.text (" ● " ++ snapshotForIndicator.label ++ " ")
                                            |> headerStyling

                                    else
                                        let
                                            hasAssertions : Bool
                                            hasAssertions =
                                                not (List.isEmpty snapshotForIndicator.assertions)
                                        in
                                        if hasAssertions then
                                            Screen.text " ◆ " |> Screen.fg Ansi.Color.green

                                        else
                                            Screen.text " ○ " |> dimStyling
                                )
                        )
            in
            Screen.lines
                ([ snapshot.screen
                 , Screen.text ""
                       , Screen.text ("  " ++ separator) |> dimStyling
                       , Screen.text ""
                       , stepIndicator
                       , Screen.text ""
                       , Screen.text footerText |> dimStyling
                       , Screen.text ""
                       , Screen.text ("  " ++ separator) |> dimStyling
                       , Screen.text ""
                       , Screen.text headerText |> headerStyling
                       , Screen.text ""
                       , Screen.concat
                            [ Screen.text "  Action: " |> dimStyling
                            , Screen.text snapshot.label
                                |> Screen.fg Ansi.Color.yellow
                                |> Screen.bold
                            , if snapshot.hasPendingEffects then
                                Screen.text "  ⟳ pending effect"
                                    |> Screen.fg Ansi.Color.magenta

                              else
                                Screen.empty
                            ]
                       ]
                    ++ (if List.isEmpty snapshot.assertions then
                            []

                        else
                            snapshot.assertions
                                |> List.map
                                    (\\assertion ->
                                        Screen.text ("    " ++ assertion)
                                            |> Screen.fg Ansi.Color.green
                                    )
                       )
                    ++ [ case snapshot.modelState of
                            Just modelStr ->
                                Screen.lines
                                    [ Screen.text ""
                                    , Screen.text "  Model:"
                                        |> Screen.fg Ansi.Color.green
                                        |> Screen.bold
                                    , modelStr
                                        |> String.lines
                                        |> List.map (\\line -> Screen.text ("    " ++ line) |> dimStyling)
                                        |> Screen.lines
                                    ]

                            Nothing ->
                                Screen.empty
                       ]
                )

        Nothing ->
            Screen.text "  No snapshots" |> Screen.dim


stepperSubscriptions : StepperModel -> Tui.Sub.Sub StepperMsg
stepperSubscriptions _ =
    Tui.Sub.onKeyPress KeyPressed


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
import Pages.Internal.DbRequest


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
    Pages.Internal.DbRequest.readMeta
        { body = BackendTask.Http.jsonBody (Encode.object (connectionFields connection))
        , decoder = dbReadPayloadBytesDecoder
        }


persistMigrated : Connection -> Db.Db -> BackendTask FatalError Db.Db
persistMigrated connection db =
    let
        wire3Bytes =
            Wire.bytesEncode (Db.w3_encode_Db db)
    in
    Pages.Internal.DbRequest.migrateWrite
        { headers = connectionHeaders connection
        , body = BackendTask.Http.bytesBody "application/octet-stream" wire3Bytes
        , decoder = Decode.succeed ()
        }
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
    Pages.Internal.DbRequest.write
        { headers = ( "x-schema-hash", schemaHash ) :: connectionHeaders connection
        , body = BackendTask.Http.bytesBody "application/octet-stream" wire3Bytes
        , decoder = Decode.succeed ()
        }


acquireLock : Connection -> BackendTask FatalError String
acquireLock connection =
    Pages.Internal.DbRequest.lockAcquire
        { body = BackendTask.Http.jsonBody (Encode.object (connectionFields connection))
        , decoder = Decode.string
        }


releaseLock : Connection -> String -> BackendTask FatalError ()
releaseLock connection token =
    Pages.Internal.DbRequest.lockRelease
        { body =
            BackendTask.Http.jsonBody
                (Encode.object
                    ([ ( "token", Encode.string token ) ]
                        ++ connectionFields connection
                    )
                )
        , decoder = Decode.succeed ()
        }


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
    { extraSourceDirs: options.extraSourceDirs }
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

// ─── Test value discovery ───────────────────────────────────────────────
//
// Discovery has two phases:
//   1. extractExposedNames: robust streaming tokenizer (vendored from
//      elm-test) returns all exposed lowercase top-level names in a file,
//      handling comments, strings, ports, and `exposing (..)` correctly.
//   2. classifyAllTestValues: reads the file once, strips comments and
//      string literals, then parses each name's top-level type annotation
//      to classify it as a Test, Test.Tui.Test, or Test.PagesProgram.Test.
//      Function types are rejected (a helper returning a Test is not itself
//      a test).

const DEFAULT_TEST_ROOTS = [
  { glob: "tests/**/*.elm", baseDir: "tests" },
  { glob: "snapshot-tests/src/**/*.elm", baseDir: "snapshot-tests/src" },
];

// Result types we recognize. Matched against the annotation's final
// component after stripping any top-level function arrows.
const VANILLA_RESULT_RE = /^(?:Test|Test\.Test)$/;
const TUI_RESULT_RE = /^(?:Test\.Tui\.Test|TuiTest\.Test)$/;
const PROGRAM_RESULT_RE = /^(?:Test\.PagesProgram\.Test|PagesProgram\.Test)$/;

/**
 * Return the exposed lowercase top-level names in an Elm module using the
 * vendored elm-test streaming tokenizer. Returns `[]` on I/O error or if
 * the file is an effect module.
 * @param {string} filePath
 * @returns {Promise<string[]>}
 */
export async function extractExposedNames(filePath) {
  try {
    return await elmTestParser.extractExposedPossiblyTests(
      filePath,
      fs.createReadStream
    );
  } catch (_) {
    return [];
  }
}

/**
 * Replace the contents of Elm line/block comments (nestable) and string
 * literals with spaces of equal length, preserving newlines. Lets later
 * regex passes scan annotations without false matches inside comments or
 * strings.
 * @param {string} source
 * @returns {string}
 */
export function stripCommentsAndStrings(source) {
  let out = "";
  let i = 0;
  const n = source.length;
  while (i < n) {
    const ch = source[i];
    const next = i + 1 < n ? source[i + 1] : "";

    if (ch === "-" && next === "-") {
      out += "  ";
      i += 2;
      while (i < n && source[i] !== "\n") {
        out += " ";
        i++;
      }
      continue;
    }

    if (ch === "{" && next === "-") {
      let depth = 1;
      out += "  ";
      i += 2;
      while (i < n && depth > 0) {
        const c = source[i];
        const c2 = i + 1 < n ? source[i + 1] : "";
        if (c === "{" && c2 === "-") {
          depth++;
          out += "  ";
          i += 2;
        } else if (c === "-" && c2 === "}") {
          depth--;
          out += "  ";
          i += 2;
        } else if (c === "\n") {
          out += "\n";
          i++;
        } else {
          out += " ";
          i++;
        }
      }
      continue;
    }

    if (ch === '"' && next === '"' && source[i + 2] === '"') {
      out += "   ";
      i += 3;
      while (i < n) {
        if (
          source[i] === '"' &&
          source[i + 1] === '"' &&
          source[i + 2] === '"'
        ) {
          out += "   ";
          i += 3;
          break;
        }
        out += source[i] === "\n" ? "\n" : " ";
        i++;
      }
      continue;
    }

    if (ch === '"') {
      out += '"';
      i++;
      while (i < n && source[i] !== '"' && source[i] !== "\n") {
        if (source[i] === "\\" && i + 1 < n) {
          out += "  ";
          i += 2;
        } else {
          out += " ";
          i++;
        }
      }
      if (i < n) {
        out += source[i] === '"' ? '"' : "\n";
        i++;
      }
      continue;
    }

    out += ch;
    i++;
  }
  return out;
}

/**
 * Extract the top-level type annotation for `name` from (already-stripped)
 * content. Returns null if no annotation is present.
 * @param {string} strippedContent
 * @param {string} name
 * @returns {string|null}
 */
function findTopLevelAnnotation(strippedContent, name) {
  const lines = strippedContent.split(/\r?\n/);
  const annotationStart = new RegExp(`^${name}\\s*:`);

  for (let i = 0; i < lines.length; i++) {
    if (!annotationStart.test(lines[i])) continue;

    const collected = [lines[i]];
    for (let j = i + 1; j < lines.length; j++) {
      if (/^[a-z][a-zA-Z0-9_]*\s*(?::|=)/.test(lines[j])) break;
      collected.push(lines[j]);
    }
    return collected.join("\n");
  }
  return null;
}

/**
 * Given an annotation like `myFn : A -> B -> C`, return `{ resultType: "C",
 * isFunction: true }`. For `myTest : Test` returns `{ resultType: "Test",
 * isFunction: false }`. The search for `->` respects paren/bracket/brace
 * nesting so record-field arrows don't count.
 * @param {string} annotation
 * @returns {{ resultType: string, isFunction: boolean }}
 */
function parseAnnotationResult(annotation) {
  const body = annotation.replace(/^[a-z][a-zA-Z0-9_]*\s*:/, "");
  let depth = 0;
  let lastArrow = -1;
  for (let i = 0; i < body.length - 1; i++) {
    const c = body[i];
    if (c === "(" || c === "[" || c === "{") depth++;
    else if (c === ")" || c === "]" || c === "}") depth--;
    else if (c === "-" && body[i + 1] === ">" && depth === 0) lastArrow = i;
  }
  const rawResult = lastArrow >= 0 ? body.slice(lastArrow + 2) : body;
  return {
    resultType: rawResult.replace(/\s+/g, " ").trim(),
    isFunction: lastArrow >= 0,
  };
}

/**
 * Classify each exposed name in a file as:
 *   - program/tui/vanilla: matched a known test type
 *   - missingAnnotation: exposed but no top-level type annotation
 *     (a forgotten annotation is the usual cause — the caller should
 *      treat this as a hard error)
 *   - nonTest: annotated but the annotation isn't a recognized test type
 *     (e.g. an exposed helper function — intentional, pass through)
 *
 * Reads and strips the file once.
 *
 * @param {string} filePath
 * @returns {Promise<{
 *   program: string[],
 *   tui: string[],
 *   vanilla: string[],
 *   missingAnnotation: string[],
 *   nonTest: string[],
 * }>}
 */
export async function classifyAllTestValues(filePath) {
  const names = await extractExposedNames(filePath);
  const empty = {
    program: [],
    tui: [],
    vanilla: [],
    missingAnnotation: [],
    nonTest: [],
  };
  if (names.length === 0) return empty;

  let content;
  try {
    content = fs.readFileSync(filePath, "utf8");
  } catch (_) {
    return empty;
  }
  const stripped = stripCommentsAndStrings(content);

  const result = {
    program: [],
    tui: [],
    vanilla: [],
    missingAnnotation: [],
    nonTest: [],
  };
  for (const name of names) {
    const annotation = findTopLevelAnnotation(stripped, name);
    if (annotation === null) {
      result.missingAnnotation.push(name);
      continue;
    }
    const { resultType, isFunction } = parseAnnotationResult(annotation);
    if (isFunction) {
      result.nonTest.push(name);
      continue;
    }
    if (PROGRAM_RESULT_RE.test(resultType)) result.program.push(name);
    else if (TUI_RESULT_RE.test(resultType)) result.tui.push(name);
    else if (VANILLA_RESULT_RE.test(resultType)) result.vanilla.push(name);
    else result.nonTest.push(name);
  }

  return result;
}

/**
 * Scan an Elm source file for exposed ProgramTest values.
 * @param {string} filePath
 * @returns {Promise<string[]>}
 */
export async function findProgramTestValues(filePath) {
  return (await classifyAllTestValues(filePath)).program;
}

/**
 * Scan an Elm source file for exposed named TUI test values.
 * @param {string} filePath
 * @returns {Promise<string[]>}
 */
export async function findTuiTestValues(filePath) {
  return (await classifyAllTestValues(filePath)).tui;
}

/**
 * Scan an Elm source file for exposed vanilla elm-explorations/test Test
 * values. Excludes the framework-specific ProgramTest and TuiTest types.
 * @param {string} filePath
 * @returns {Promise<string[]>}
 */
export async function findVanillaTestValues(filePath) {
  return (await classifyAllTestValues(filePath)).vanilla;
}

export async function discoverProgramTestModules(
  searchRoots = DEFAULT_TEST_ROOTS
) {
  return (await discoverAllTestModules(searchRoots)).program;
}

export async function discoverTuiTestModules(
  searchRoots = DEFAULT_TEST_ROOTS
) {
  return (await discoverAllTestModules(searchRoots)).tui;
}

export async function discoverVanillaTestModules(
  searchRoots = DEFAULT_TEST_ROOTS
) {
  return (await discoverAllTestModules(searchRoots)).vanilla;
}

/**
 * Walk the search roots once, classifying every file. Returns the three
 * test buckets plus a `warnings` list naming files that have at least one
 * classified test AND at least one exposed-but-unclassified value (a
 * likely-forgotten annotation the user should know about).
 *
 * @param {{glob: string, baseDir: string}[]} [searchRoots]
 * @returns {Promise<{
 *   program: {moduleName: string, file: string, values: string[]}[],
 *   tui: {moduleName: string, file: string, values: string[]}[],
 *   vanilla: {moduleName: string, file: string, values: string[]}[],
 *   missingAnnotations: {file: string, moduleName: string, names: string[]}[],
 * }>}
 */
export async function discoverAllTestModules(
  searchRoots = DEFAULT_TEST_ROOTS
) {
  const program = [];
  const tui = [];
  const vanilla = [];
  const missingAnnotations = [];

  for (const { glob, baseDir } of searchRoots) {
    const files = globby.globbySync([glob]);
    for (const file of files) {
      const classified = await classifyAllTestValues(file);
      const moduleName = path
        .relative(baseDir, file)
        .replace(/\.elm$/, "")
        .replace(/[/\\]/g, ".");

      if (classified.program.length > 0) {
        program.push({ moduleName, file, values: classified.program });
      }
      if (classified.tui.length > 0) {
        tui.push({ moduleName, file, values: classified.tui });
      }
      if (classified.vanilla.length > 0) {
        vanilla.push({ moduleName, file, values: classified.vanilla });
      }

      if (classified.missingAnnotation.length > 0) {
        missingAnnotations.push({
          file,
          moduleName,
          names: classified.missingAnnotation,
        });
      }
    }
  }
  return { program, tui, vanilla, missingAnnotations };
}

/**
 * Build a hard-error message describing exposed values that have no
 * top-level type annotation. Discovery treats these as "forgotten
 * annotation" footguns and fails rather than skipping them silently.
 *
 * @param {{file: string, names: string[]}[]} missingAnnotations
 * @returns {string}
 */
export function missingAnnotationsError(missingAnnotations) {
  const lines = [
    "Exposed values without a type annotation.",
    "",
    "These values are exposed from test modules but have no top-level type",
    "annotation, so elm-pages can't tell whether they're tests. Either add a",
    "type annotation or remove them from the module's exposing list.",
    "",
  ];
  for (const { file, names } of missingAnnotations) {
    for (const name of names) {
      lines.push(`  ${file}: ${name}`);
    }
  }
  lines.push("");
  lines.push("Expected test annotations:");
  lines.push("  : Test                 (elm-explorations/test)");
  lines.push("  : Test.Tui.Test        (TUI test)");
  lines.push("  : TestApp.ProgramTest  (page/program test)");
  return lines.join("\n");
}
