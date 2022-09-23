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
  try {
    await compileCliApp(
      // { debug: true },
      {},
      `Generate.elm`,
      path.join(process.cwd(), "elm-stuff/elm-pages-codegen.js"),
      path.join(__dirname, "../../codegen"),

      path.join(process.cwd(), "elm-stuff/elm-pages-codegen.js")
    );
  } catch (error) {
    console.log(restoreColorSafe(error));
    process.exit(1);
    // throw error;
  }

  // TODO use uncached require here to prevent stale code from running

  const promise = new Promise((resolve, reject) => {
    const elmPagesCodegen = require(path.join(
      process.cwd(),
      "./elm-stuff/elm-pages-codegen.js"
    )).Elm.Generate;

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

function emptyRouteParams(name) {
  return routeHelpers.parseRouteParams(name).length === 0;
}

/**
 * @param {string} segment
 * @returns {'static' | 'dynamic' | 'optional' | 'index' | 'required-splat' | 'optional-splat'}
 */
function segmentKind(segment) {
  if (segment === "Index") {
    return "index";
  }
  const routeParamMatch = segment.match(/([A-Z][A-Za-z0-9]*)(_?_?)$/);
  const segmentKind = (routeParamMatch && routeParamMatch[2]) || "";
  const isSplat = routeParamMatch && routeParamMatch[1] === "SPLAT";
  if (segmentKind === "") {
    return "static";
  } else if (segmentKind === "_") {
    return isSplat ? "required-splat" : "dynamic";
  } else if (segmentKind === "__") {
    return isSplat ? "optional-splat" : "optional";
  } else {
    throw "Unhandled segmentKind";
  }
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

/**
 * @param {string[]} name
 */
function routeRegex(name) {
  const parsedParams = routeHelpers.parseRouteParams(name);
  const includesOptional = parsedParams.some(
    (param) => param.kind === "optional"
  );
  const params = routeHelpers.routeParams(name);
  const parserCode = name
    .flatMap((section) => {
      const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)(_?_?)$/);
      const maybeParam = routeParamMatch && routeParamMatch[1];
      switch (segmentKind(section)) {
        case "static": {
          return [`\\\\/` + camelToKebab(section)];
        }
        case "index": {
          return [`\\\\/`];
        }
        case "dynamic": {
          return [`\\\\/(?:([^/]+))`];
        }
        case "required-splat": {
          return [`\\\\/(.*)`];
        }
        case "optional-splat": {
          return [`(.*)`];
        }
        case "optional": {
          return [`\\\\/(?:([^/]+))?`];
        }
      }
    })
    .join("");

  const toRoute = `\\matches ->
      case matches of
          [ ${parsedParams
            .flatMap((parsedParam) => {
              switch (parsedParam.kind) {
                case "optional": {
                  return parsedParam.name;
                }
                case "dynamic": {
                  return `Just ${parsedParam.name}`;
                }
                case "required-splat": {
                  return `Just splat`;
                }
                case "optional-splat": {
                  return `splat`;
                }
              }
            })
            .join(", ")} ] ->
              Just ${
                parsedParams.length === 0
                  ? pathNormalizedName(name)
                  : `( ${pathNormalizedName(name)} { ${parsedParams.map(
                      (param) => {
                        return `${param.name} = ${prefixThing(param)}${
                          param.name
                        }`;
                      }
                    )} } )`
              }
          _ ->
              Nothing

  `;

  return { pattern: parserCode, toRoute };
}

function prefixThing(param) {
  switch (param.kind) {
    case "optional-splat": {
      return "Pages.Internal.Router.fromOptionalSplat ";
    }
    case "required-splat": {
      return "Pages.Internal.Router.toNonEmpty ";
    }
    default: {
      return "";
    }
  }
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
 * @param {string[]} name
 */
function routePathList(name) {
  return withoutTrailingIndex(name)
    .map((section) => {
      const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)_$/);
      const maybeParam = routeParamMatch && routeParamMatch[1];
      if (maybeParam) {
        return `params.${maybeParam.toLowerCase()}`;
      } else {
        return `"${camelToKebab(section)}"`;
      }
    })
    .join(", ");
}

/**
 * @param {string[]} name
 */
function withoutTrailingIndex(name) {
  if (name[name.length - 1] === "Index") {
    return name.slice(0, -1);
  } else {
    return name;
  }
}
/**
 * Convert Strings from camelCase to kebab-case
 * @param {string} input
 * @returns {string}
 */
function camelToKebab(input) {
  return input.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
}
/**
 * @param {string[]} name
 */
function isParameterizedRoute(name) {
  return name.some((section) => section.includes("_"));
}

/**
 * @param {string[]} name
 */
function pathNormalizedName(name) {
  return name.join("__");
}

/**
 * @param {string[]} name
 */
function moduleName(name) {
  return name.join(".");
}

function paramAsElmString(param) {
  switch (param.kind) {
    case "dynamic": {
      return "stringToString";
    }
    case "optional": {
      return "maybeToString";
    }
    case "required-splat": {
      return "nonEmptyToString";
    }
    case "optional-splat": {
      return "listToString";
    }
  }
}

module.exports = { generateTemplateModuleConnector, sortTemplates };
