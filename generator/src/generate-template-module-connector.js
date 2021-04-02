const globby = require("globby");
const path = require("path");

function generateTemplateModuleConnector() {
  const templates = globby
    .sync(["src/Template/*.elm"], {})
    .map((file) => path.basename(file, ".elm"));

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

${templates.map((name) => `import Template.${name}`).join("\n")}


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
      .map((name) => `Model${name} Template.${name}.Model\n`)
      .join("    | ")}
    | NotFound


type Route
    = ${templates.map((name) => `Route${name} {}\n`).join("    | ")}

urlToRoute : Url.Url -> Maybe Route
urlToRoute =
    Parser.parse (Parser.oneOf routes)


routes : List (Parser (Route -> a) a)
routes =
    [ ${templates.map((name) => `${nameToParser(name)}\n`).join("    , ")}
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
      .map((name) => `Msg${name} Template.${name}.Msg\n`)
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
              `Just (Route${name} s) ->
            StaticHttp.map2
                (\\data globalData ->
                    { view =
                        \\model ->
                            case model.page of
                                Model${name} subModel ->
                                    Template.${name}.template.view
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
                                                        |> Shared.template.map Msg${name}
                                                    )
                                           )

                                _ ->
                                    { title = "Model mismatch", body = Html.text <| "Model mismatch" }
                    , head = Template.${name}.template.head
                        { static = data
                        , sharedStatic = globalData
                        , path = page.path
                        }
                    }
                )
                (Template.${name}.template.staticData)
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
            case maybePagePath  |> Maybe.andThen .metadata of
                Nothing ->
                    ( NotFound, Cmd.none )

                ${templates
                  .map(
                    (name) => `Just (Route${name} routeParams) ->
                    Template.${name}.template.init routeParams
                        |> Tuple.mapBoth Model${name} (Cmd.map Msg${name})

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
        Msg${name} msg_ ->
            let
                ( updatedPageModel, pageCmd, ( newGlobalModel, newGlobalCmd ) ) =
                    case ( model.page, model.current |> Maybe.andThen .metadata ) of
                        ( Model${name} pageModel, Just (Route${name} routeParams) ) ->
                            Template.${name}.template.update
                                routeParams
                                msg_
                                pageModel
                                model.global
                                |> mapBoth Model${name} (Cmd.map Msg${name})
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
        ( Model${name} templateModel, Route${name} routeParams ) ->
            Template.${name}.template.subscriptions
                routeParams
                path
                templateModel
                model.global
                |> Sub.map Msg${name}
`
          )
          .join("\n        ")}


        _ ->
            Sub.none


mainTemplate { site } =
    Pages.Platform.init
        { init = init Nothing
        , urlToRoute = urlToRoute
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
 * @param {string} name
 */
function nameToParser(name) {
  return `Parser.map (Route${name} {}) (Parser.s "${name.toLowerCase()}")`;
}

module.exports = { generateTemplateModuleConnector };
