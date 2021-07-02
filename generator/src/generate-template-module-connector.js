const globby = require("globby");
const path = require("path");
const mm = require("micromatch");
const routeHelpers = require("./route-codegen-helpers");

/**
 * @param {'browser' | 'cli'} phase
 */
function generateTemplateModuleConnector(phase) {
  const templates = globby.sync(["src/Page/**/*.elm"], {}).map((file) => {
    const captures = mm.capture("src/Page/**/*.elm", file);
    if (captures) {
      return path.join(captures[0], captures[1]).split(path.sep);
    } else {
      return [];
    }
  });
  if (templates.length <= 0) {
    throw {
      path: "",
      name: "TemplateModulesBeta",
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

  return {
    mainModule: `port module TemplateModulesBeta exposing (..)

import Api
import ApiRoute
import Browser.Navigation
import Route exposing (Route)
import View
import Json.Decode
import Json.Encode
import Pages.Flags
import ${
      phase === "browser"
        ? "Pages.Internal.Platform"
        : "Pages.Internal.Platform.Cli"
    }
import Pages.Manifest as Manifest
import Shared
import Site
import Head
import Html exposing (Html)
import NotFoundReason
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import RoutePattern
import Url
import DataSource exposing (DataSource)
import QueryParams

${templates.map((name) => `import Page.${name.join(".")}`).join("\n")}


type alias Model =
    { global : Shared.Model
    , page : PageModel
    , current :
        Maybe
            { path :
                { path : Path
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            , pageUrl : Maybe PageUrl
            }
    }


type PageModel
    = ${templates
      .map(
        (name) =>
          `Model${pathNormalizedName(name)} Page.${moduleName(name)}.Model\n`
      )
      .join("    | ")}
    | NotFound




type Msg
    = MsgGlobal Shared.Msg
    | OnPageChange
        { protocol : Url.Protocol
        , host : String
        , port_ : Maybe Int
        , path : Path
        , query : Maybe String
        , fragment : Maybe String
        , metadata : Maybe Route
        }
    | ${templates
      .map(
        (name) =>
          `Msg${pathNormalizedName(name)} Page.${moduleName(name)}.Msg\n`
      )
      .join("    | ")}


type PageData
    = Data404NotFoundPage____
    | ${templates
      .map(
        (name) =>
          `Data${pathNormalizedName(name)} Page.${moduleName(name)}.Data\n`
      )
      .join("    | ")}



view :
    { path : Path
    , frontmatter : Maybe Route
    }
    -> Maybe PageUrl
    -> Shared.Data
    -> PageData
    ->
        { view : Model -> { title : String, body : Html Msg }
        , head : List Head.Tag
        }
view page maybePageUrl globalData pageData =
    case ( page.frontmatter, pageData ) of
        ${templates
          .map(
            (name) =>
              `( Just ${
                emptyRouteParams(name)
                  ? `Route.${routeHelpers.routeVariant(name)}`
                  : `(Route.${routeHelpers.routeVariant(name)} s)`
              }, Data${routeHelpers.routeVariant(name)} data ) ->
                  { view =
                      \\model ->
                          case model.page of
                              Model${pathNormalizedName(name)} subModel ->
                                  Page.${moduleName(name)}.page.view
                                      maybePageUrl
                                      model.global
                                      subModel
                                      { data = data
                                      , sharedData = globalData
                                      , routeParams = ${
                                        emptyRouteParams(name) ? "{}" : "s"
                                      }
                                      , path = page.path
                                      }
                                      |> View.map Msg${pathNormalizedName(name)}
                                      |> Shared.template.view globalData page model.global MsgGlobal

                              _ ->
                                  { title = "Model mismatch", body = Html.text <| "Model mismatch" }
                  , head = Page.${moduleName(name)}.page.head
                      { data = data
                      , sharedData = globalData
                      , routeParams = ${emptyRouteParams(name) ? "{}" : "s"}
                      , path = page.path
                      }
                  }
`
          )
          .join("\n\n        ")}
        _ ->
            { head = []
            , view =
                \\_ ->
                    { title = "Page not found"
                    , body =
                            Html.div [] 
                            [ Html.text "This page could not be found."
                            ]
                    }

            }



init :
    Maybe Shared.Model
    -> Pages.Flags.Flags
    -> Shared.Data
    -> PageData
    -> Maybe Browser.Navigation.Key
    ->
        Maybe
            { path :
                { path : Path
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            , pageUrl : Maybe PageUrl
            }
    -> ( Model, Cmd Msg )
init currentGlobalModel userFlags sharedData pageData navigationKey maybePagePath =
    let
        ( sharedModel, globalCmd ) =
            currentGlobalModel |> Maybe.map (\\m -> ( m, Cmd.none )) |> Maybe.withDefault (Shared.template.init navigationKey userFlags maybePagePath)

        ( templateModel, templateCmd ) =
            case ( ( Maybe.map2 Tuple.pair (maybePagePath |> Maybe.andThen .metadata) (maybePagePath |> Maybe.map .path) ), pageData ) of
                ${templates
                  .map(
                    (name) => `( Just ( ${
                      emptyRouteParams(name)
                        ? `Route.${routeHelpers.routeVariant(name)}`
                        : `(Route.${routeHelpers.routeVariant(
                            name
                          )} routeParams)`
                    }, justPath ), Data${pathNormalizedName(
                      name
                    )} thisPageData ) ->
                    Page.${moduleName(name)}.page.init
                        (Maybe.andThen .pageUrl maybePagePath)
                        sharedModel
                        { data = thisPageData
                        , sharedData = sharedData
                        , routeParams = ${
                          emptyRouteParams(name) ? "{}" : "routeParams"
                        }
                        , path = justPath.path
                        }
                        |> Tuple.mapBoth Model${pathNormalizedName(
                          name
                        )} (Cmd.map Msg${pathNormalizedName(name)})
`
                  )
                  .join("\n                ")}
                _ ->
                    ( NotFound, Cmd.none )
    in
    ( { global = sharedModel
      , page = templateModel
      , current = maybePagePath
      }
    , Cmd.batch
        [ templateCmd
        , globalCmd |> Cmd.map MsgGlobal
        ]
    )



update : Shared.Data -> PageData -> Maybe Browser.Navigation.Key -> Msg -> Model -> ( Model, Cmd Msg )
update sharedData pageData navigationKey msg model =
    case msg of
        MsgGlobal msg_ ->
            let
                ( sharedModel, globalCmd ) =
                    Shared.template.update msg_ model.global
            in
            ( { model | global = sharedModel }
            , globalCmd |> Cmd.map MsgGlobal
            )

        OnPageChange record ->
            (init (Just model.global) Pages.Flags.PreRenderFlags sharedData pageData navigationKey <|
                Just
                    { path =
                        { path = record.path
                        , query = record.query
                        , fragment = record.fragment
                        }
                    , metadata = record.metadata
                    , pageUrl =
                        Just
                            { protocol = record.protocol
                            , host = record.host
                            , port_ = record.port_
                            , path = record.path
                            , query = record.query |> Maybe.map QueryParams.fromString
                            , fragment = record.fragment
                            }
                    }
            )
                |> (\\( updatedModel, cmd ) ->
                        case Shared.template.onPageChange of
                            Nothing ->
                                ( updatedModel, cmd )

                            Just thingy ->
                                let
                                    ( updatedGlobalModel, globalCmd ) =
                                        Shared.template.update
                                            (thingy
                                                { path = record.path
                                                , query = record.query
                                                , fragment = record.fragment
                                                }
                                            )
                                            model.global
                                in
                                ( { updatedModel
                                    | global = updatedGlobalModel
                                  }
                                , Cmd.batch [ cmd, Cmd.map MsgGlobal globalCmd ]
                                )
                   )


        ${templates
          .map(
            (name) => `
        Msg${pathNormalizedName(name)} msg_ ->
            let
                ( updatedPageModel, pageCmd, ( newGlobalModel, newGlobalCmd ) ) =
                    case ( model.page, pageData, Maybe.map3 (\\a b c -> ( a, b, c )) (model.current |> Maybe.andThen .metadata) (model.current |> Maybe.andThen .pageUrl) (model.current |> Maybe.map .path) ) of
                        ( Model${pathNormalizedName(
                          name
                        )} pageModel, Data${pathNormalizedName(
              name
            )} thisPageData, Just ( ${routeHelpers.destructureRoute(
              name,
              "routeParams"
            )}, pageUrl, justPage ) ) ->
                            Page.${moduleName(name)}.page.update
                                pageUrl
                                { data = thisPageData
                                , sharedData = sharedData
                                , routeParams = ${routeHelpers.referenceRouteParams(
                                  name,
                                  "routeParams"
                                )}
                                , path = justPage.path
                                }
                                navigationKey
                                msg_
                                pageModel
                                model.global
                                |> mapBoth Model${pathNormalizedName(
                                  name
                                )} (Cmd.map Msg${pathNormalizedName(name)})
                                |> (\\( a, b, c ) ->
                                        case c of
                                            Just sharedMsg ->
                                                ( a, b, Shared.template.update (Shared.template.sharedMsg sharedMsg) model.global )

                                            Nothing ->
                                                ( a, b, ( model.global, Cmd.none ) )
                                   )

                        _ ->
                            ( model.page, Cmd.none, ( model.global, Cmd.none ) )
            in
            ( { model | page = updatedPageModel, global = newGlobalModel }
            , Cmd.batch [ pageCmd, newGlobalCmd |> Cmd.map MsgGlobal ]
            )
`
          )
          .join("\n        ")}


type alias SiteConfig =
    { canonicalUrl : String
    , manifest : Manifest.Config
    }

templateSubscriptions : Maybe Route -> Path -> Model -> Sub Msg
templateSubscriptions route path model =
    case ( model.page, route ) of
        ${templates
          .map(
            (name) => `
        ( Model${pathNormalizedName(
          name
        )} templateModel, Just ${routeHelpers.destructureRoute(
              name,
              "routeParams"
            )} ) ->
            Page.${moduleName(name)}.page.subscriptions
                Nothing -- TODO wire through value
                ${routeHelpers.referenceRouteParams(name, "routeParams")}
                path
                templateModel
                model.global
                |> Sub.map Msg${pathNormalizedName(name)}
`
          )
          .join("\n        ")}


        _ ->
            Sub.none


main : ${
      phase === "browser"
        ? "Pages.Internal.Platform.Program Model Msg PageData Shared.Data"
        : "Pages.Internal.Platform.Cli.Program (Maybe Route)"
    }
main =
    ${
      phase === "browser"
        ? "Pages.Internal.Platform.application"
        : "Pages.Internal.Platform.Cli.cliApplication"
    }
        { init = init Nothing
        , urlToRoute = Route.urlToRoute
        , routeToPath = \\route -> route |> Maybe.map Route.routeToPath |> Maybe.withDefault []
        , site = Site.config
        , getStaticRoutes = getStaticRoutes |> DataSource.map (List.map Just)
        , handleRoute = handleRoute
        , view = view
        , update = update
        , subscriptions =
            \\route path model ->
                Sub.batch
                    [ Shared.template.subscriptions path model.global |> Sub.map MsgGlobal
                    , templateSubscriptions route path model
                    ]
        , onPageChange = OnPageChange
        , toJsPort = toJsPort
        , fromJsPort = fromJsPort identity
        , data = dataForRoute
        , sharedData = Shared.template.data
        , apiRoutes = \\htmlToString -> pathsToGenerateHandler :: routePatterns :: manifestHandler :: Api.routes getStaticRoutes htmlToString
        , pathPatterns = routePatterns3
        }

dataForRoute : Maybe Route -> DataSource PageData
dataForRoute route =
    case route of
        Nothing ->
            DataSource.succeed Data404NotFoundPage____
        ${templates
          .map(
            (name) =>
              `Just ${
                emptyRouteParams(name)
                  ? `Route.${routeHelpers.routeVariant(name)}`
                  : `(Route.${routeHelpers.routeVariant(name)} routeParams)`
              } ->\n            Page.${name.join(
                "."
              )}.page.data ${routeHelpers.referenceRouteParams(
                name,
                "routeParams"
              )} |> DataSource.map Data${routeHelpers.routeVariant(name)}`
          )
          .join("\n        ")}

handleRoute : Maybe Route -> DataSource (Maybe NotFoundReason.NotFoundReason)
handleRoute maybeRoute =
    case maybeRoute of
        Nothing ->
            DataSource.succeed Nothing

        ${templates
          .map(
            (name) =>
              `Just (Route.${routeHelpers.routeVariant(name)}${
                routeHelpers.parseRouteParams(name).length === 0
                  ? ""
                  : " routeParams"
              }) ->\n            Page.${name.join(
                "."
              )}.page.handleRoute { moduleName = [ ${name
                .map((part) => `"${part}"`)
                .join(", ")} ], routePattern = ${routeHelpers.toElmPathPattern(
                name
              )} } (\\param -> [ ${routeHelpers
                .parseRouteParams(name)
                .map(
                  (param) =>
                    `( "${param.name}", ${paramAsElmString(param)} param.${
                      param.name
                    } )`
                )
                .join(", ")} ]) ${routeHelpers.referenceRouteParams(
                name,
                "routeParams"
              )}`
          )
          .join("\n        ")}


stringToString : String -> String
stringToString string =
    "\\"" ++ string ++ "\\""


nonEmptyToString : ( String, List String ) -> String
nonEmptyToString ( first, rest ) =
    "( "
        ++ stringToString first
        ++ ", [ "
        ++ (rest
                |> List.map stringToString
                |> String.join ", "
           )
        ++ " ] )"


listToString : List String -> String
listToString strings =
    "[ "
        ++ (strings
                |> List.map stringToString
                |> String.join ", "
           )
        ++ " ]"


maybeToString : Maybe String -> String
maybeToString maybeString =
    case maybeString of
        Just string ->
            "Just " ++ stringToString string

        Nothing ->
            "Nothing"




routePatterns : ApiRoute.Done ApiRoute.Response
routePatterns =
    ApiRoute.succeed
        (Json.Encode.list
            (\\{ kind, pathPattern } ->
                Json.Encode.object
                    [ ( "kind", Json.Encode.string kind )
                    , ( "pathPattern", Json.Encode.string pathPattern )
                    ]
            )
            [ ${sortTemplates(templates)
              .map((name) => {
                return `{ kind = Page.${moduleName(
                  name
                )}.page.kind, pathPattern = "${routeHelpers.toPathPattern(
                  name
                )}" }`;
              })
              .join("\n            , ")}
          
            ]
            |> (\\json -> DataSource.succeed { body = Json.Encode.encode 0 json })
        )
        |> ApiRoute.literal "route-patterns.json"
        |> ApiRoute.single


routePatterns2 : List String
routePatterns2 =
    [ ${sortTemplates(templates)
      .map((name) => {
        return `"${routeHelpers.toPathPattern(name)}"`;
      })
      .join("\n    , ")}
    ]


routePatterns3 : List RoutePattern.RoutePattern
routePatterns3 =
    [ ${sortTemplates(templates)
      .map((name) => {
        return `${routeHelpers.toElmPathPattern(name)}`;
      })
      .join("\n    , ")}
    ]

getStaticRoutes : DataSource (List Route)
getStaticRoutes =
    DataSource.combine
        [ ${templates
          .map((name) => {
            return `Page.${moduleName(
              name
            )}.page.staticRoutes |> DataSource.map (List.map ${
              emptyRouteParams(name)
                ? `(\\_ -> Route.${pathNormalizedName(name)}))`
                : `Route.${pathNormalizedName(name)})`
            }`;
          })
          .join("\n        , ")}
        ]
        |> DataSource.map List.concat


pathsToGenerateHandler : ApiRoute.Done ApiRoute.Response
pathsToGenerateHandler =
    ApiRoute.succeed
        (getStaticRoutes
            |> DataSource.map
                (List.map
                    (\\route ->
                        route
                            |> Route.toPath
                            |> Path.toAbsolute
                    )
                )
            |> DataSource.map
                (\\list ->
                    { body =
                        list
                            |> Json.Encode.list Json.Encode.string
                            |> Json.Encode.encode 0
                    }
                )
        )
        |> ApiRoute.literal "all-paths.json"
        |> ApiRoute.single


manifestHandler : ApiRoute.Done ApiRoute.Response
manifestHandler =
    ApiRoute.succeed
        (getStaticRoutes
            |> DataSource.map (List.map Just)
            |> DataSource.andThen
                (\\resolvedRoutes ->
                    Site.config resolvedRoutes
                        |> .data
                        |> DataSource.map
                            (\\data ->
                                (Site.config resolvedRoutes |> .manifest) data
                                    |> manifestToFile (Site.config resolvedRoutes |> .canonicalUrl)
                            )
                )
        )
        |> ApiRoute.literal "manifest.json"
        |> ApiRoute.single


manifestToFile : String -> Manifest.Config -> { body : String }
manifestToFile resolvedCanonicalUrl manifestConfig =
    manifestConfig
        |> Manifest.toJson resolvedCanonicalUrl
        |> (\\manifestJsonValue ->
                { body = Json.Encode.encode 0 manifestJsonValue
                }
           )


port toJsPort : Json.Encode.Value -> Cmd msg

port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg


mapBoth : (a -> b) -> (c -> d) -> ( a, c, e ) -> ( b, d, e )
mapBoth fnA fnB ( a, b, c ) =
    ( fnA a, fnB b, c )
`,
    routesModule: `module Route exposing (Route(..), link, matchers, routeToPath, toLink, urlToRoute, toPath)

{-|

@docs Route, link, matchers, routeToPath, toLink, urlToRoute, toPath

-}


import Html exposing (Attribute, Html)
import Html.Attributes as Attr
import Path exposing (Path)
import Router


{-| -}
type Route
    = ${templates.map(routeHelpers.routeVariantDefinition).join("\n    | ")}


{-| -}
urlToRoute : { url | path : String } -> Maybe Route
urlToRoute url =
    Router.firstMatch matchers url.path


{-| -}
matchers : List (Router.Matcher Route)
matchers =
    [ ${sortTemplates(templates)
      .map(
        (name) => `{ pattern = "^${routeRegex(name).pattern}$"
      , toRoute = ${routeRegex(name).toRoute}
     }\n`
      )
      .join("    , ")}
    ]


{-| -}
routeToPath : Route -> List String
routeToPath route =
    case route of
        ${templates
          .map(
            (name) =>
              `${routeHelpers.routeVariant(name)}${
                routeHelpers.parseRouteParams(name).length === 0
                  ? ""
                  : ` params`
              } ->\n           List.concat [ ${routeHelpers
                .parseRouteParamsWithStatic(name)
                .map((param) => {
                  switch (param.kind) {
                    case "static": {
                      return param.name === "Index"
                        ? `[]`
                        : `[ "${camelToKebab(param.name)}" ]`;
                    }
                    case "optional": {
                      return `Router.maybeToList params.${param.name}`;
                    }
                    case "required-splat": {
                      return `Router.nonEmptyToList params.${param.name}`;
                    }
                    case "dynamic": {
                      return `[ params.${param.name} ]`;
                    }
                    case "optional-splat": {
                      return `params.${param.name}`;
                    }
                  }
                })} ]`
          )
          .join("\n        ")}

{-| -}
toPath : Route -> Path
toPath route =
    route |> routeToPath |> String.join "/" |> Path.fromString

{-| -}
toLink : (List (Attribute msg) -> tag) -> Route -> tag
toLink toAnchorTag route =
    toAnchorTag
        [ Attr.href ("/" ++ (routeToPath route |> String.join "/"))
        , Attr.attribute "elm-pages:prefetch" ""
        ]


{-| -}
link : Route -> List (Attribute msg) -> List (Html msg) -> Html msg
link route attributes children =
    toLink
        (\\anchorAttrs ->
            Html.a
                (anchorAttrs ++ attributes)
                children
        )
        route
`,
  };
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
          return [`(?:\\\\/([^/]+))?`];
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
      return "Router.fromOptionalSplat ";
    }
    case "required-splat": {
      return "Router.toNonEmpty ";
    }
    default: {
      return "";
    }
  }
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
