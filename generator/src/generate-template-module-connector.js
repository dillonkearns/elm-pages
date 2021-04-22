const globby = require("globby");
const path = require("path");
const mm = require("micromatch");
const routeHelpers = require("./route-codegen-helpers");

/**
 * @param {'browser' | 'cli'} phase
 */
function generateTemplateModuleConnector(phase) {
  const templates = globby.sync(["src/Template/**/*.elm"], {}).map((file) => {
    const captures = mm.capture("src/Template/**/*.elm", file);
    if (captures) {
      return path.join(captures[0], captures[1]).split("/");
    } else {
      return [];
    }
  });
  if (templates.length <= 0) {
    throw `I couldn't find any Page Templates. Try using elm-pages add Index to get started with your first page!`;
  }

  return {
    mainModule: `port module TemplateModulesBeta exposing (..)

import Browser
import Browser.Navigation
import Route exposing (Route)
import Document
import Json.Decode
import Json.Encode
import ${
      phase === "browser"
        ? "Pages.Internal.Platform"
        : "Pages.Internal.Platform.Cli"
    }
import Pages.Internal.Platform.ToJsPayload
import Pages.Manifest as Manifest
import Shared
import Site
import Head
import Html exposing (Html)
import Pages.PagePath exposing (PagePath)
import Url
import Url.Parser as Parser exposing ((</>), Parser)
import DataSource exposing (DataSource)

${templates.map((name) => `import Template.${name.join(".")}`).join("\n")}


type alias Model =
    { global : Shared.Model
    , page : TemplateModel
    , current :
        Maybe
            { path :
                { path : PagePath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            }
    }


type TemplateModel
    = ${templates
      .map(
        (name) =>
          `Model${pathNormalizedName(name)} Template.${moduleName(
            name
          )}.Model\n`
      )
      .join("    | ")}
    | NotFound




type Msg
    = MsgGlobal Shared.Msg
    | OnPageChange
        { path : PagePath
        , query : Maybe String
        , fragment : Maybe String
        , metadata : Maybe Route
        }
    | ${templates
      .map(
        (name) =>
          `Msg${pathNormalizedName(name)} Template.${moduleName(name)}.Msg\n`
      )
      .join("    | ")}


type PageStaticData
    = Data404NotFoundPage____
    | ${templates
      .map(
        (name) =>
          `Data${pathNormalizedName(name)} Template.${moduleName(
            name
          )}.StaticData\n`
      )
      .join("    | ")}



view :
    { path : PagePath
    , frontmatter : Maybe Route
    }
    -> Shared.StaticData
    -> PageStaticData
    ->
        { view : Model -> { title : String, body : Html Msg }
        , head : List Head.Tag
        }
view page globalData staticData =
    case ( page.frontmatter, staticData ) of
        ${templates
          .map(
            (name) =>
              `( Just (Route.${routeHelpers.routeVariant(
                name
              )} s), Data${routeHelpers.routeVariant(name)} data ) ->
                  { view =
                      \\model ->
                          case model.page of
                              Model${pathNormalizedName(name)} subModel ->
                                  Template.${moduleName(name)}.template.view
                                      subModel
                                      model.global
                                      { static = data
                                      , sharedStatic = globalData
                                      , routeParams = s
                                      , path = page.path
                                      }
                                      |> (\\{ title, body } ->
                                              Shared.template.view
                                                  globalData
                                                  page
                                                  model.global
                                                  MsgGlobal
                                                  ({ title = title, body = body }
                                                      |> Document.map Msg${pathNormalizedName(
                                                        name
                                                      )}
                                                  )
                                          )

                              _ ->
                                  { title = "Model mismatch", body = Html.text <| "Model mismatch" }
                  , head = Template.${moduleName(name)}.template.head
                      { static = data
                      , sharedStatic = globalData
                      , routeParams = s
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
    -> Shared.StaticData
    -> PageStaticData
    -> Maybe Browser.Navigation.Key
    ->
        Maybe
            { path :
                { path : PagePath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            }
    -> ( Model, Cmd Msg )
init currentGlobalModel sharedStaticData pageStaticData navigationKey maybePagePath =
    let
        ( sharedModel, globalCmd ) =
            currentGlobalModel |> Maybe.map (\\m -> ( m, Cmd.none )) |> Maybe.withDefault (Shared.template.init navigationKey maybePagePath)

        ( templateModel, templateCmd ) =
            case ( ( Maybe.map2 Tuple.pair (maybePagePath |> Maybe.andThen .metadata) (maybePagePath |> Maybe.map .path) ), pageStaticData ) of
                ${templates
                  .map(
                    (name) => `( Just ( (Route.${routeHelpers.routeVariant(
                      name
                    )} routeParams), justPath ), Data${pathNormalizedName(
                      name
                    )} thisPageData ) ->
                    Template.${moduleName(name)}.template.init
                        { static = thisPageData
                        , sharedStatic = sharedStaticData
                        , routeParams = routeParams
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



update : Shared.StaticData -> PageStaticData -> Maybe Browser.Navigation.Key -> Msg -> Model -> ( Model, Cmd Msg )
update sharedStaticData pageStaticData navigationKey msg model =
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
            (init (Just model.global) sharedStaticData pageStaticData navigationKey <|
                Just
                    { path =
                        { path = record.path
                        , query = record.query
                        , fragment = record.fragment
                        }
                    , metadata = record.metadata
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
                    case ( model.page, pageStaticData, Maybe.map2 Tuple.pair (model.current |> Maybe.andThen .metadata) (model.current |> Maybe.map .path) ) of
                        ( Model${pathNormalizedName(
                          name
                        )} pageModel, Data${pathNormalizedName(
              name
            )} thisPageData, Just ( (Route.${routeHelpers.routeVariant(
              name
            )} routeParams), justPage ) ) ->
                            Template.${moduleName(name)}.template.update
                                { static = thisPageData
                                , sharedStatic = sharedStaticData
                                , routeParams = routeParams
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
                                                ( a, b, Shared.template.update (Shared.SharedMsg sharedMsg) model.global )

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

templateSubscriptions : Maybe Route -> PagePath -> Model -> Sub Msg
templateSubscriptions route path model =
    case ( model.page, route ) of
        ${templates
          .map(
            (name) => `
        ( Model${pathNormalizedName(
          name
        )} templateModel, Just (Route.${routeHelpers.routeVariant(
              name
            )} routeParams) ) ->
            Template.${moduleName(name)}.template.subscriptions
                routeParams
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
        ? "Pages.Internal.Platform.Program Model Msg PageStaticData Shared.StaticData"
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
        , routeToPath = Route.routeToPath
        , site = Site.config
        , getStaticRoutes = getStaticRoutes
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
        , staticData = staticDataForRoute
        , sharedStaticData = Shared.template.staticData
        , generateFiles =
            getStaticRoutes
                |> DataSource.andThen
                    (\\resolvedStaticRoutes ->
                        DataSource.map2 (::)
                            (manifestGenerator
                                resolvedStaticRoutes
                            )
                            (Site.config
                                resolvedStaticRoutes
                                |> .generateFiles
                            )
                    )
        }

staticDataForRoute : Maybe Route -> DataSource PageStaticData
staticDataForRoute route =
    case route of
        Nothing ->
            DataSource.succeed Data404NotFoundPage____
        ${templates
          .map(
            (name) =>
              `Just (Route.${routeHelpers.routeVariant(
                name
              )} routeParams) ->\n            Template.${name.join(
                "."
              )}.template.staticData routeParams |> DataSource.map Data${routeHelpers.routeVariant(
                name
              )}`
          )
          .join("\n        ")}

handleRoute : Maybe Route -> DataSource Bool
handleRoute maybeRoute =
    case maybeRoute of
        Nothing ->
            DataSource.succeed False

        ${templates
          .map(
            (name) =>
              `Just (Route.${routeHelpers.routeVariant(
                name
              )} routeParams) ->\n            ${handleRoute(name)}`
          )
          .join("\n        ")}



getStaticRoutes : DataSource (List (Maybe Route))
getStaticRoutes =
    DataSource.combine
        [ ${templates
          .map((name) => {
            if (isParameterizedRoute(name)) {
              return `Template.${moduleName(
                name
              )}.template.staticRoutes |> DataSource.map (List.map Route.${pathNormalizedName(
                name
              )})`;
            } else {
              return `DataSource.succeed [ Route.${routeHelpers.routeVariant(
                name
              )} {} ]`;
            }
          })
          .join("\n        , ")}
        ]
        |> DataSource.map List.concat
        |> DataSource.map (List.map Just)


manifestGenerator : List ( Maybe Route ) -> DataSource (Result anyError { path : List String, content : String })
manifestGenerator resolvedRoutes =
    Site.config resolvedRoutes
        |> .staticData
        |> DataSource.map
            (\\data ->
                (Site.config resolvedRoutes |> .manifest) data
                    |> manifestToFile (Site.config resolvedRoutes |> .canonicalUrl)
            )


manifestToFile : String -> Manifest.Config -> Result anyError { path : List String, content : String }
manifestToFile resolvedCanonicalUrl manifestConfig =
    manifestConfig
        |> Manifest.toJson resolvedCanonicalUrl
        |> (\\manifestJsonValue ->
                Ok
                    { path = [ "manifest.json" ]
                    , content = Json.Encode.encode 0 manifestJsonValue
                    }
           )



port toJsPort : Json.Encode.Value -> Cmd msg

port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg


mapDocument : Browser.Document Never -> Browser.Document mapped
mapDocument document =
    { title = document.title
    , body = document.body |> List.map (Html.map never)
    }


mapBoth fnA fnB ( a, b, c ) =
    ( fnA a, fnB b, c )
`,
    routesModule: `module Route exposing (..)

import Url
import Url.Parser as Parser exposing ((</>), Parser)


type Route
    = ${templates.map(routeHelpers.routeVariantDefinition).join("\n    | ")}


urlToRoute : Url.Url -> Maybe Route
urlToRoute url =
    Parser.parse (Parser.oneOf routes) url


routes : List (Parser (Route -> a) a)
routes =
    [ ${templates.map((name) => `${routeParser(name)}\n`).join("    , ")}
    ]


routeToPath : Maybe Route -> List String
routeToPath maybeRoute =
    case maybeRoute of
        Nothing ->
            []
        ${templates
          .map(
            (name) =>
              `Just (${routeHelpers.routeVariant(
                name
              )} params) ->\n            [ ${routePathList(name)} ]`
          )
          .join("\n        ")}
`,
  };
}

/**
 * @param {string[]} name
 */
function routeParser(name) {
  const params = routeHelpers.routeParams(name);
  const parserCode = name
    .map((section) => {
      const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)_$/);
      const maybeParam = routeParamMatch && routeParamMatch[1];
      if (maybeParam) {
        return `Parser.string`;
      } else if (section === "Index") {
        // TODO give an error if it isn't the final element
        return "Parser.top";
      } else {
        return `Parser.s "${camelToKebab(section)}"`;
      }
    })
    .join(" </> ");
  if (params.length > 0) {
    return `Parser.map (\\${params.join(" ")} -> ${pathNormalizedName(
      name
    )} { ${params.map((param) => `${param} = ${param}`)} }) (${parserCode})`;
  } else {
    return `Parser.map (${pathNormalizedName(name)} {}) (${parserCode})`;
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

/**
 *
 * @param {string[]} name
 */
function handleRoute(name) {
  if (routeHelpers.routeParams(name).length > 0) {
    return `Template.${name.join(
      "."
    )}.template.staticRoutes |> DataSource.map (List.member routeParams)`;
  } else {
    return `DataSource.succeed True`;
  }
}

module.exports = { generateTemplateModuleConnector };
