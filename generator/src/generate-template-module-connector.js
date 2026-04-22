import * as globby from "globby";
import * as path from "path";
import { default as mm } from "micromatch";
import * as routeHelpers from "./route-codegen-helpers.js";
import { restoreColorSafe } from "./error-formatter.js";
import { fileURLToPath, pathToFileURL } from "url";
import { spawnSync } from "child_process";
import which from "which";

/**
 * Runs elm-review analysis on the original app/ folder to extract ephemeral fields info.
 * This info is used to generate custom CLI encoders that skip ephemeral fields.
 * @returns {Object<string, {ephemeralFields: string[], persistentFields: string[]}>}
 */
async function analyzeEphemeralFields() {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);

  const lamderaPath = await which("lamdera");
  // Use server-review config which uses ServerDataTransform rule
  // This rule detects ephemeral fields by tracking which Data fields are used
  // in client-facing contexts (view function) vs server-only contexts (head function)
  const result = spawnSync(
    "elm-review",
    [
      "--report",
      "json",
      "--namespace",
      "elm-pages",
      "--config",
      path.join(__dirname, "../../generator/server-review"),
      "--elmjson",
      "elm.json",
      "--compiler",
      lamderaPath,
    ],
    {
      encoding: "utf8",
      maxBuffer: 10 * 1024 * 1024, // 10MB buffer for large outputs
    }
  );

  // Just collect module names that have ephemeral fields (simple list)
  const routesWithEphemeral = [];

  try {
    const jsonOutput = JSON.parse(result.stdout);
    if (jsonOutput.errors) {
      for (const fileErrors of jsonOutput.errors) {
        for (const error of fileErrors.errors) {
          if (
            error.message &&
            error.message.startsWith("EPHEMERAL_FIELDS_JSON:")
          ) {
            const jsonStr = error.message.slice("EPHEMERAL_FIELDS_JSON:".length);
            const data = JSON.parse(jsonStr);
            // Only add if there are actually ephemeral fields
            if (data.ephemeralFields && data.ephemeralFields.length > 0) {
              routesWithEphemeral.push(data.module);
            }
          }
        }
      }
    }
  } catch (e) {
    // If parsing fails, return empty list (no ephemeral field optimization)
    console.warn(
      "Warning: Could not parse elm-review output for ephemeral fields analysis:",
      e.message
    );
  }

  return routesWithEphemeral;
}

/**
 * @param {string} basePath
 * @param {'browser' | 'cli'} phase
 * @param {{ skipEphemeralAnalysis?: boolean, routesWithEphemeral?: string[] }} [options]
 */
export async function generateTemplateModuleConnector(basePath, phase, options = {}) {
  const templates = globby
    .globbySync(["app/Route/**/*.elm"], {})
    .map((file) => {
      const captures = mm.capture("app/Route/**/*.elm", file);
      if (captures) {
        return path.join(captures[0], captures[1]).split(path.sep);
      } else {
        return [];
      }
    });
  if (templates.length <= 0) {
    throw {
      path: "",
      name: "Main",
      problems: [
        {
          title: "Could not generate entrypoint",
          message: [
            `I couldn't find any Page Templates. Try creating your first page by running: \n\n`,
            {
              bold: false,
              underline: false,
              color: "yellow",
              string: "elm-pages add Index",
            },
          ],
        },
      ],
    };
  }

  // For CLI phase, detect which routes have ephemeral fields
  // (used to generate correct encoders/decoders in Main.elm)
  // Skip in dev mode since the server-review codemod that creates Ephemeral types isn't run
  let routesWithEphemeral = [];
  if (phase === "cli" && !options.skipEphemeralAnalysis) {
    if (options.routesWithEphemeral) {
      // Use pre-computed results from the server codemod's analysis.
      // This ensures Main.elm only references Ephemeral types that the codemod actually created.
      routesWithEphemeral = options.routesWithEphemeral;
    } else {
      routesWithEphemeral = await analyzeEphemeralFields();
    }
  }

  let elmCodegenFiles = null;
  try {
    elmCodegenFiles = await runElmCodegenCli(
      sortTemplates(templates),
      basePath,
      phase,
      routesWithEphemeral
    );
  } catch (error) {
    console.log(restoreColorSafe(error));
    throw error;
  }
  const routesModule = elmCodegenFiles[0].contents;
  const newMain = elmCodegenFiles[1].contents;

  return {
    mainModule: newMain,
    routesModule,
    fetcherModules: templates.map((name) => {
      return [name, fetcherModule(name)];
    }),
    testAppModule: testAppModule(templates),
  };
}

async function runElmCodegenCli(templates, basePath, phase, routesWithEphemeral) {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  const filePath = pathToFileURL(
    path.join(__dirname, `../../codegen/elm-pages-codegen.cjs`)
  ).href;

  const promise = new Promise(async (resolve, reject) => {
    const elmPagesCodegen = (await import(filePath)).default.Elm.Generate;

    const app = elmPagesCodegen.init({
      flags: {
        templates: templates,
        basePath,
        phase,
        // Simple list of module names that have ephemeral fields
        ephemeralFields: routesWithEphemeral,
      },
    });
    if (app.ports.onSuccessSend) {
      app.ports.onSuccessSend.subscribe(resolve);
    }
    if (app.ports.onInfoSend) {
      app.ports.onInfoSend.subscribe((info) => console.log(info));
    }
    if (app.ports.onFailureSend) {
      app.ports.onFailureSend.subscribe(reject);
    }
  });
  const filesToGenerate = await promise;

  return filesToGenerate;
}

/**
 *
 * @param {string[][]} templates
 * @returns
 */
export function sortTemplates(templates) {
  return templates.sort((first, second) => {
    const a = sortScore(first);
    const b = sortScore(second);
    if (b.splatScore === a.splatScore) {
      if (b.staticSegments === a.staticSegments) {
        return b.dynamicSegments - a.dynamicSegments;
      } else {
        return b.staticSegments - a.staticSegments;
      }
    } else {
      return a.splatScore - b.splatScore;
    }
  });
}

/**
 * @param {string[]} name
 */
function sortScore(name) {
  const parsedParams = routeHelpers.parseRouteParamsWithStatic(name);
  return parsedParams.reduce(
    (currentScore, segment) => {
      switch (segment.kind) {
        case "dynamic": {
          return {
            ...currentScore,
            dynamicSegments: currentScore.dynamicSegments + 1,
          };
        }
        case "static": {
          return {
            ...currentScore,
            staticSegments: currentScore.staticSegments + 1,
          };
        }
        case "optional": {
          return {
            ...currentScore,
            splatScore: 10,
          };
        }
        case "required-splat": {
          return {
            ...currentScore,
            splatScore: 100,
          };
        }
        case "optional-splat": {
          return {
            ...currentScore,
            splatScore: 100,
          };
        }
      }
    },
    { staticSegments: 0, dynamicSegments: 0, splatScore: 0 }
  );
}

function fetcherModule(name) {
  let moduleName = name.join(".");
  // TODO need to account for splat routes/etc.
  let modulePath = name.join("/");
  let fetcherPath = routeHelpers
    .parseRouteParamsWithStatic(name)
    .map((param) => {
      switch (param.kind) {
        case "static": {
          return param.name === "Index"
            ? `[]`
            : `[ "${camelToKebab(param.name)}" ]`;
        }
        case "optional": {
          return `Pages.Internal.Router.maybeToList params.${param.name}`;
        }
        case "required-splat": {
          return `Pages.Internal.Router.nonEmptyToList params.${param.name}`;
        }
        case "dynamic": {
          return `[ params.${param.name} ]`;
        }
        case "optional-splat": {
          return `params.${param.name}`;
        }
      }
    })
    .join(", ");

  return `module Fetcher.${moduleName} exposing (submit)

{-| -}

import Bytes exposing (Bytes)
import Bytes.Decode
import Http
import Pages.Fetcher
import Route.${moduleName}


submit :
    (Result Http.Error Route.${moduleName}.ActionData -> msg)
    ->
        { fields : List ( String, String )
        , headers : List ( String, String )
        }
    -> Pages.Fetcher.Fetcher msg
submit toMsg options =
    { decoder =
        \\bytesResult ->
            bytesResult
                |> Result.andThen
                    (\\okBytes ->
                        okBytes
                            |> Bytes.Decode.decode Route.${moduleName}.w3_decode_ActionData
                            |> Result.fromMaybe (Http.BadBody "Couldn't decode bytes.")
                    )
                |> toMsg
    , fields = options.fields
    , headers = ("elm-pages-action-only", "true") :: options.headers
        , url = ${
          fetcherPath === ""
            ? 'Just "/content.dat"'
            : `[ ${fetcherPath}, [ "content.dat" ] ] |> List.concat |> String.join "/" |> Just`
        }
    }
    |> Pages.Fetcher.Fetcher
`;
}

/**
 * Generate the TestApp module used by framework-driven ProgramTests.
 * It exposes a single start helper backed by Test.PagesProgram.start,
 * which drives the real elm-pages runtime for higher-fidelity route tests.
 * @param {string[][]} templates
 * @returns {string}
 */
function testAppModule(templates) {
  if (templates.length === 0) {
    return `module TestApp exposing (..)

{-| Generated test configurations. No routes found. -}
`;
  }

  return `module TestApp exposing (start, ProgramTest)

{-| Generated test module for elm-pages route testing.

The recommended way to test routes is with \`start\`, which drives the real
elm-pages framework (Platform.init/update/view) for full fidelity:

    import TestApp
    import Test.BackendTask as BackendTaskTest
    import Test.PagesProgram as PagesProgram

    TestApp.start "/" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ ... ]
        |> PagesProgram.done

This module is generated by elm-pages. Do not edit manually.
-}

import BackendTask exposing (BackendTask)
import Bytes
import Dict
import Effect exposing (Effect)
import ErrorPage
import FatalError exposing (FatalError)
import Html
import Html.Styled
import Main
import Pages.Flags
import Pages.Internal.Platform
import Shared
import Test.PagesProgram
import Test.PagesProgram.CookieJar as CookieJar
import Time


{-| Type alias for framework-driven test values. Use this in type annotations
so the visual test runner can discover your tests:

    myTest : TestApp.ProgramTest
    myTest =
        TestApp.start "/" testSetup
            |> PagesProgram.ensureViewHas [ ... ]

The \`virtualFs\` field is the expanded shape of the framework-internal
virtual filesystem + environment record. Users don't read or construct
it — it's tracked behind the scenes by the simulators in
[\`Test.BackendTask\`](Test-BackendTask).

-}
type alias ProgramTest =
    Test.PagesProgram.ProgramTest
        { platformModel : Pages.Internal.Platform.Model Main.Model Main.PageData Main.ActionData Shared.Data
        , virtualFs :
            { files : Dict.Dict String String
            , binaryFiles : Dict.Dict String Bytes.Bytes
            , stdin : Maybe String
            , env : Dict.Dict String String
            , time : Maybe Time.Posix
            , timeZone : Maybe { defaultOffset : Int, eras : List { start : Int, offset : Int } }
            , timeZonesByName : Dict.Dict String { defaultOffset : Int, eras : List { start : Int, offset : Int } }
            , randomSeed : Maybe Int
            , whichCommands : Dict.Dict String String
            , tempDirCounter : Int
            }
        , cookieJar : CookieJar.CookieJar
        , pendingDataError : Maybe String
        , pendingDataPath : Maybe String
        , pendingActionBody : Maybe { body : String, path : String }
        }
        (Pages.Internal.Platform.Msg Main.Msg Main.PageData Main.ActionData Shared.Data ErrorPage.ErrorPage)


{-| Start a full-fidelity elm-pages test. Drives the real elm-pages framework
so that shared data, shared view, navigation, form submission, and all other
framework behavior works identically to production.

Use Test.BackendTask.init to set up the virtual filesystem, then pass
it alongside the initial path:

    TestApp.start "/"
        (BackendTaskTest.init
            |> BackendTaskTest.withFile "greeting.txt" "Hello!"
        )
        |> PagesProgram.ensureViewHas [ Selector.text "Hello!" ]
        |> PagesProgram.done

-}
start =
    Test.PagesProgram.start Effect.testPerform Main.config
`;
}


/**
 * Convert a route name array to a camelCase config name.
 * e.g., ["Blog", "Slug_"] -> "blogSlug_"
 * @param {string[]} name
 * @returns {string}
 */
function routeConfigName(name) {
  if (name.length === 1 && name[0] === "Index") {
    return "index";
  }
  return name
    .map((part, i) => {
      if (i === 0) {
        return part.charAt(0).toLowerCase() + part.slice(1);
      }
      return part;
    })
    .join("");
}

/**
 * Generate a default routeParams expression for a route.
 * @param {string[]} name
 * @returns {string}
 */
/**
 * Check if a route name has dynamic segments (ending in _).
 * @param {string[]} name
 * @returns {boolean}
 */
function hasDynamicSegments(name) {
  return name.some((part) => part.endsWith("_"));
}

/**
 * Convert Strings from camelCase to kebab-case
 * @param {string} input
 * @returns {string}
 */
function camelToKebab(input) {
  return input.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
}
