const globby = require("globby")
const path = require("path")


function generateTemplateModuleConnector() {
    const templates = globby.sync(["src/Template/*.elm"], {}).map(file => path.basename(file, '.elm'))

    return `module TemplateDemultiplexer exposing (..)

import Browser
import Global
import GlobalMetadata as M exposing (Metadata)
import Head
import Html exposing (Html)
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.Platform
import Pages.StaticHttp as StaticHttp
import SiteConfig
${templates.map(name => `import Template.${name}`).join("\n")}


type alias Model =
    { global : Global.Model
    , page : TemplateModel
    , current :
        Maybe
            { path :
                { path : PagePath Pages.PathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Metadata
            }
    }


type TemplateModel
    = ${templates.map(name => `Model${name} Template.${name}.Model\n`).join("    | ")}
    | NotFound



type Msg
    = MsgGlobal Global.Msg
    | OnPageChange
        { path : PagePath Pages.PathKey
        , query : Maybe String
        , fragment : Maybe String
        , metadata : Metadata
        }
    | ${templates.map(name => `Msg${name} Template.${name}.Msg\n`).join("    | ")}


view :
    List ( PagePath Pages.PathKey, Metadata )
    ->
        { path : PagePath Pages.PathKey
        , frontmatter : Metadata
        }
    ->
        StaticHttp.Request
            { view : Model -> Global.RenderedBody -> { title : String, body : Html Msg }
            , head : List (Head.Tag Pages.PathKey)
            }
view siteMetadata page =
    case page.frontmatter of
        ${templates.map(name =>
        `M.Metadata${name} metadata ->
            StaticHttp.map2
                (\\data globalData ->
                    { view =
                        \\model rendered ->
                            case model.page of
                                Model${name} subModel ->
                                    Template.${name}.template.view
                                        siteMetadata
                                        data
                                        subModel
                                        metadata
                                        rendered
                                        |> (\\{ title, body } ->
                                                Global.view
                                                    globalData
                                                    page
                                                    model.global
                                                    MsgGlobal
                                                    ({ title = title, body = body }
                                                        |> Global.map Msg${name}
                                                    )
                                           )

                                _ ->
                                    { title = "", body = Html.text "" }
                    , head = Template.${name}.template.head data page.path metadata
                    }
                )
                (Template.${name}.template.staticData siteMetadata)
                (Global.staticData siteMetadata)
`).join("\n\n        ")
        }


init :
    Maybe Global.Model
    ->
        Maybe
            { path :
                { path : PagePath Pages.PathKey
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : Metadata
            }
    -> ( Model, Cmd Msg )
init currentGlobalModel maybePagePath =
    ( { global = currentGlobalModel |> Maybe.withDefault (Global.init maybePagePath)
      , page =
            case maybePagePath |> Maybe.map .metadata of
                Nothing ->
                    NotFound

                Just meta ->
                    case meta of
                        ${templates.map(name => `M.Metadata${name} metadata ->
                            Template.${name}.template.init metadata
                                |> Tuple.first
                                |> Model${name}

`).join("\n                        ")}
      , current = maybePagePath
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MsgGlobal msg_ ->
            let
                ( globalModel, globalCmd ) =
                    Global.update msg_ model.global
            in
            ( { model | global = globalModel }, globalCmd |> Cmd.map MsgGlobal )

        OnPageChange record ->
            init (Just model.global) <|
                Just
                    { path =
                        { path = record.path
                        , query = record.query
                        , fragment = record.fragment
                        }
                    , metadata = record.metadata
                    }

        ${templates.map(name => `
        Msg${name} msg_ ->
            let
                ( updatedPageModel, pageCmd ) =
                    case ( model.page, model.current |> Maybe.map .metadata ) of
                        ( Model${name} pageModel, Just (M.Metadata${name} metadata) ) ->
                            Template.${name}.template.update
                                metadata
                                msg_
                                pageModel
                                |> Tuple.mapBoth Model${name} (Cmd.map Msg${name})

                        _ ->
                            ( model.page, Cmd.none )
            in
            ( { model | page = updatedPageModel, global = save updatedPageModel model.global }, pageCmd )
`
        ).join("\n        ")}



save : TemplateModel -> Global.Model -> Global.Model
save model globalModel=
    case model of
        ${templates.map(name => `Model${name} m ->
            Template.${name}.template.save m globalModel
`
        ).join("\n        ")}

        NotFound ->
            globalModel



mainTemplate { documents, manifest, canonicalSiteUrl, subscriptions } =
    Pages.Platform.init
        { init = init Nothing
        , view = view
        , update = update
        , subscriptions = subscriptions
        , documents = documents
        , onPageChange = Just OnPageChange
        , manifest = manifest -- SiteConfig.manifest
        , canonicalSiteUrl = canonicalSiteUrl -- SiteConfig.canonicalUrl
        , internals = Pages.internals
        }


mapDocument : Browser.Document Never -> Browser.Document mapped
mapDocument document =
    { title = document.title
    , body = document.body |> List.map (Html.map never)
    }
`
}

module.exports = { generateTemplateModuleConnector }