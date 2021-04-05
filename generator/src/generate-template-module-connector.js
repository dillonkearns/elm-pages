const globby = require("globby");
const path = require("path");
const mm = require("micromatch");

function generateTemplateModuleConnector() {
  const templates = globby.sync(["src/Template/**/*.elm"], {}).map((file) => {
    const captures = mm.capture("src/Template/**/*.elm", file);
    if (captures) {
      return path.join(captures[0], captures[1]).split("/");
    } else {
      return [];
    }
  });

  return `module TemplateModulesBeta exposing (..)

import Browser
import Pages.Manifest as Manifest
import Shared
import NoMetadata exposing (NoMetadata(..))
import Head
import Html exposing (Html)
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.Platform
import Url
import Url.Parser as Parser exposing ((</>), Parser)
import Pages.StaticHttp as StaticHttp

${templates.map((name) => `import Template.${name.join(".")}`).join("\n")}


type alias Model =
    { global : Shared.Model
    , page : TemplateModel
    , current :
        Maybe
            { path :
                { path : PagePath Pages.PathKey
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


type Route
    = ${templates.map(routeVariantDefinition).join("    | ")}

urlToRoute : Url.Url -> Maybe Route
urlToRoute url =
    Parser.parse (Parser.oneOf routes) url


routeToPath : Maybe Route -> List String
routeToPath maybeRoute =
    case maybeRoute of
        Nothing ->
            []
        ${templates
          .map(
            (name) =>
              `Just (${routeVariant(
                name
              )} params) ->\n            [ ${routePathList(name)} ]`
          )
          .join("\n        ")}


routes : List (Parser (Route -> a) a)
routes =
    [ ${templates.map((name) => `${routeParser(name)}\n`).join("    , ")}
    ]


type Msg
    = MsgGlobal Shared.Msg
    | OnPageChange
        { path : PagePath Pages.PathKey
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


view :
    { path : PagePath Pages.PathKey
    , frontmatter : Maybe Route
    }
    ->
        StaticHttp.Request
            { view : Model -> { title : String, body : Html Msg }
            , head : List (Head.Tag Pages.PathKey)
            }
view page =
    case page.frontmatter of
        Nothing ->
            StaticHttp.fail <| "Page not found: " ++ Pages.PagePath.toString page.path
        ${templates
          .map(
            (name) =>
              `Just (${routeVariant(name)} s) ->
            StaticHttp.map2
                (\\data globalData ->
                    { view =
                        \\model ->
                            case model.page of
                                Model${pathNormalizedName(name)} subModel ->
                                    Template.${moduleName(name)}.template.view
                                        subModel
                                        model.global
                                        { static = data
                                        , sharedStatic = globalData
                                        , path = page.path
                                        }
                                        |> (\\{ title, body } ->
                                                Shared.template.view
                                                    globalData
                                                    page
                                                    model.global
                                                    MsgGlobal
                                                    ({ title = title, body = body }
                                                        |> Shared.template.map Msg${pathNormalizedName(
                                                          name
                                                        )}
                                                    )
                                           )

                                _ ->
                                    { title = "Model mismatch", body = Html.text <| "Model mismatch" }
                    , head = Template.${moduleName(name)}.template.head
                        { static = data
                        , sharedStatic = globalData
                        , path = page.path
                        }
                    }
                )
                (Template.${moduleName(name)}.template.staticData s)
                (Shared.template.staticData)
`
          )
          .join("\n\n        ")}


init :
    Maybe Shared.Model
    ->
        Maybe
            { path :
                { path : PagePath Pages.PathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Maybe Route
            }
    -> ( Model, Cmd Msg )
init currentGlobalModel maybePagePath =
    let
        ( sharedModel, globalCmd ) =
            currentGlobalModel |> Maybe.map (\\m -> ( m, Cmd.none )) |> Maybe.withDefault (Shared.template.init maybePagePath)

        ( templateModel, templateCmd ) =
            case maybePagePath |> Maybe.andThen .metadata of
                Nothing ->
                    ( NotFound, Cmd.none )

                ${templates
                  .map(
                    (name) => `Just (${routeVariant(name)} routeParams) ->
                    Template.${moduleName(name)}.template.init routeParams
                        |> Tuple.mapBoth Model${pathNormalizedName(
                          name
                        )} (Cmd.map Msg${pathNormalizedName(name)})

`
                  )
                  .join("\n                ")}
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



update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
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
            (init (Just model.global) <|
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
                    case ( model.page, model.current |> Maybe.andThen .metadata ) of
                        ( Model${pathNormalizedName(
                          name
                        )} pageModel, Just (${routeVariant(
              name
            )} routeParams) ) ->
                            Template.${moduleName(name)}.template.update
                                routeParams
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
    , manifest : Manifest.Config Pages.PathKey
    }

templateSubscriptions : Route -> PagePath Pages.PathKey -> Model -> Sub Msg
templateSubscriptions route path model =
    case ( model.page, route ) of
        ${templates
          .map(
            (name) => `
        ( Model${pathNormalizedName(name)} templateModel, ${routeVariant(
              name
            )} routeParams ) ->
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


mainTemplate { site } =
    Pages.Platform.init
        { init = init Nothing
        , urlToRoute = urlToRoute
        , routeToPath = routeToPath
        , getStaticRoutes =
            StaticHttp.combine
                [ StaticHttp.succeed
                    [ ${templates
                      .filter((name) => !isParameterizedRoute(name))
                      .map((name) => `${routeVariant(name)} {}`)
                      .join("\n                    , ")}
                    ]
                , Template.Blog.Slug_.routes |> StaticHttp.map (List.map RouteBlog__Slug_)
                ]
                |> StaticHttp.map List.concat
                |> StaticHttp.map (List.map Just)
        , view = \\_ -> view
        , update = update
        , subscriptions =
            \\metadata path model ->
                Sub.batch
                    [ Shared.template.subscriptions NoMetadata path model.global |> Sub.map MsgGlobal
                    , templateSubscriptions (RouteBlog {}) path model
                    ]
        , onPageChange = Just OnPageChange
        , manifest = site.manifest
        , canonicalSiteUrl = site.canonicalUrl
        , internals = Pages.internals
        }



mapDocument : Browser.Document Never -> Browser.Document mapped
mapDocument document =
    { title = document.title
    , body = document.body |> List.map (Html.map never)
    }


mapBoth fnA fnB ( a, b, c ) =
    ( fnA a, fnB b, c )
`;
}

/**
 * @param {string[]} name
 */
function routeParser(name) {
  if (name.some((section) => section.includes("_"))) {
    return `Parser.map (\\slug -> RouteBlog__Slug_ { slug = slug }) (Parser.s "blog" </> Parser.string)`;
  } else {
    return `Parser.map (Route${pathNormalizedName(
      name
    )} {}) (Parser.s "${name.join("TODO").toLowerCase()}")`;
  }
}

/**
 * @param {string[]} name
 */
function routeVariantDefinition(name) {
  return `${routeVariant(name)} { ${routeParams(name).map(
    (param) => `${param} : String`
  )} }`;
}

/**
 * @param {string[]} name
 */
function routeParams(name) {
  return name
    .map((section) => {
      const routeParamMatch = section.match(/([A-Z][A-Za-z0-9]*)_$/);
      const maybeParam = routeParamMatch && routeParamMatch[1];
      return maybeParam && toFieldName(maybeParam);
    })
    .filter((maybeParam) => maybeParam !== null);
}

/**
 * @param {string } name
 */
function toFieldName(name) {
  return name.toLowerCase();
}

/**
 * @param {string[]} name
 */
function routeVariant(name) {
  return `Route${name.join("__")}`;
}

/**
 * @param {string[]} name
 */
function routePathList(name) {
  return name
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

module.exports = { generateTemplateModuleConnector };
