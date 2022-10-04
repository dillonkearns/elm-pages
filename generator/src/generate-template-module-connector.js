const globby = require("globby");
const path = require("path");
const mm = require("micromatch");
const routeHelpers = require("./route-codegen-helpers");
const { runElmCodegenInstall } = require("./elm-codegen");
const { compileCliApp } = require("./compile-elm");
const { restoreColorSafe } = require("./error-formatter");

/**
 * @param {string} basePath
 * @param {'browser' | 'cli'} phase
 */
async function generateTemplateModuleConnector(basePath, phase) {
  const templates = globby.sync(["app/Route/**/*.elm"], {}).map((file) => {
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
  let elmCodegenFiles = null;
  try {
    elmCodegenFiles = await runElmCodegenCli(
      sortTemplates(templates),
      basePath,
      phase
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
  };
}

async function runElmCodegenCli(templates, basePath, phase) {
  // await runElmCodegenInstall();
  // try {
  //   await compileCliApp(
  //     // { debug: true },
  //     {},
  //     `Generate.elm`,
  //     path.join(process.cwd(), "elm-stuff/elm-pages-codegen.js"),
  //     path.join(__dirname, "../../codegen"),

  //     path.join(process.cwd(), "elm-stuff/elm-pages-codegen.js")
  //   );
  // } catch (error) {
  //   console.log(restoreColorSafe(error));
  //   process.exit(1);
  //   // throw error;
  // }

  const filePath = path.join(__dirname, `../../codegen/elm-pages-codegen.js`);

  // TODO use uncached require here to prevent stale code from running

  const promise = new Promise((resolve, reject) => {
    const elmPagesCodegen = require(filePath).Elm.Generate;
      // path.join(
      // process.cwd(),
      // "./elm-stuff/elm-pages-codegen.js")

    const app = elmPagesCodegen.init({
      flags: { templates: templates, basePath, phase },
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
  console.dir(filesToGenerate.map((file) => file.path));

  return filesToGenerate;
}


/**
 *
 * @param {string[][]} templates
 * @returns
 */
function sortTemplates(templates) {
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
import FormDecoder
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
 * Convert Strings from camelCase to kebab-case
 * @param {string} input
 * @returns {string}
 */
function camelToKebab(input) {
  return input.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
}


module.exports = { generateTemplateModuleConnector, sortTemplates };
