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
 * @returns {string} Elm source code for the Pages.Db module
 */
export function generatePagesDbModule(schemaHash) {
  return `module Pages.Db exposing (get, update, transaction)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Base64
import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import Db
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Lamdera.Wire3 as Wire


schemaHash : String
schemaHash =
    "${schemaHash}"


get : BackendTask FatalError Db.Db
get =
    BackendTask.Internal.Request.request
        { name = "db-read"
        , body = BackendTask.Http.jsonBody (Encode.string schemaHash)
        , expect =
            Bytes.Decode.signedInt32 Bytes.BE
                |> Bytes.Decode.andThen
                    (\\length ->
                        if length <= 0 then
                            Bytes.Decode.succeed Nothing

                        else
                            Bytes.Decode.bytes length
                                |> Bytes.Decode.map Just
                    )
                |> BackendTask.Http.expectBytes
        }
        |> BackendTask.andThen
            (\\maybeBytes ->
                case maybeBytes of
                    Nothing ->
                        BackendTask.succeed Db.init

                    Just bytes ->
                        case Wire.bytesDecode Db.w3_decode_Db bytes of
                            Just db ->
                                BackendTask.succeed db

                            Nothing ->
                                BackendTask.fail
                                    (FatalError.build
                                        { title = "db.bin decode failed"
                                        , body = "Data is corrupted. Run \`elm-pages db reset\`."
                                        }
                                    )
            )


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
    BackendTask.Internal.Request.request
        { name = "db-write"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "hash", Encode.string schemaHash )
                    , ( "data", Encode.string base64Data )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


acquireLock : BackendTask FatalError String
acquireLock =
    BackendTask.Internal.Request.request
        { name = "db-lock-acquire"
        , body = BackendTask.Http.jsonBody Encode.null
        , expect = BackendTask.Http.expectJson Decode.string
        }


releaseLock : String -> BackendTask FatalError ()
releaseLock token =
    BackendTask.Internal.Request.request
        { name = "db-lock-release"
        , body = BackendTask.Http.jsonBody (Encode.string token)
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }
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

  // Generate Pages.Db module if this script uses the database
  if (options.usesDb) {
    const { computeSchemaHash } = await import("../db-schema.js");
    const dbElmPath = await findDbElm(projectDirectory, sourceDirectory);
    const schemaHash = await computeSchemaHash(dbElmPath);
    ensureDirSync(`${projectDirectory}/elm-stuff/elm-pages/.elm-pages/Pages`);
    await writeFileIfChanged(
      path.join(
        `${projectDirectory}/elm-stuff/elm-pages/.elm-pages/Pages/Db.elm`
      ),
      generatePagesDbModule(schemaHash)
    );
  }

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
the initial value used when no db.bin file exists yet.`;
}
