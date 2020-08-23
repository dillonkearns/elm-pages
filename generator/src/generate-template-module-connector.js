const globby = require("globby")
const path = require("path")


function generateTemplateModuleConnector(staticRoutes) {
    const templates = globby.sync(["src/Template/*.elm"], {}).map(file => path.basename(file, '.elm'))

    return `module TemplateDemultiplexer exposing (..)

import Browser
import Element exposing (Element)
import Global
import GlobalMetadata as M exposing (Metadata)
import Head
import Html exposing (Html)
import MarkdownRenderer
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.Platform
import Pages.StaticHttp as StaticHttp
import SiteConfig
${templates.map(name => `import Template.${name}`).join("\n")}


type alias Model =
    { global : Global.Model
    , page : TemplateModel
    }


type TemplateModel
    = ${templates.map(name => `Model${name} Template.${name}.Model\n`).join("    | ")}


type Msg
    = MsgGlobal Global.Msg
    | OnPageChange
        { path : PagePath Pages.PathKey
        , query : Maybe String
        , fragment : Maybe String
        , metadata : Metadata
        }
    | ${templates.map(name => `Msg${name} Template.${name}.Msg\n`).join("    | ")}


type alias View =
    ( MarkdownRenderer.TableOfContents, List (Element Never) )


view :
    List ( PagePath Pages.PathKey, Metadata )
    ->
        { path : PagePath Pages.PathKey
        , frontmatter : Metadata
        }
    ->
        StaticHttp.Request
            { view : Model -> View -> { title : String, body : Html Msg }
            , head : List (Head.Tag Pages.PathKey)
            }
view siteMetadata page =
    case page.frontmatter of
        ${templates.map(name =>
        `M.Metadata${name} metadata ->
            StaticHttp.map2
                (\data globalData ->
                    { view =
                        \model rendered ->
                            case model.page of
                                Model${name} subModel ->
                                    Template.${name}.template.view
                                        siteMetadata
                                        data
                                        subModel
                                        metadata
                                        rendered
                                        |> (\{ title, body } ->
                                                Global.wrapBody
                                                    globalData
                                                    page
                                                    model.global
                                                    MsgGlobal
                                                    { title = title
                                                    , body =
                                                        -- Template.BlogPost.liftViewMsg
                                                        Element.map never body
                                                    }
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
    Maybe
        { path :
            { path : PagePath Pages.PathKey
            , query : Maybe String
            , fragment : Maybe String
            }
        , metadata : Metadata
        }
    -> ( Model, Cmd Msg )
init maybePagePath =
    ( { global = Global.init maybePagePath
      , page =
            case maybePagePath |> Maybe.map .metadata of
                Nothing ->
                    Debug.todo ""

                Just meta ->
                    case meta of
                        M.MetadataBlogPost metadata ->
                            Template.BlogPost.template.init metadata
                                |> Tuple.first
                                |> ModelBlogPost

                        M.MetadataShowcase metadata ->
                            Template.Showcase.template.init metadata
                                |> Tuple.first
                                |> ModelShowcase

                        M.MetadataPage metadata ->
                            Template.Page.template.init metadata
                                |> Tuple.first
                                |> ModelPage

                        M.MetadataBlogIndex metadata ->
                            Template.BlogIndex.template.init metadata
                                |> Tuple.first
                                |> ModelBlogIndex

                        M.MetadataDocumentation metadata ->
                            Template.Documentation.template.init metadata
                                |> Tuple.first
                                |> ModelDocumentation
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MsgBlogPost msg_ ->
            ( model, Cmd.none )

        MsgGlobal msg_ ->
            let
                ( globalModel, globalCmd ) =
                    Global.update msg_ model.global
            in
            ( { model | global = globalModel }, globalCmd |> Cmd.map MsgGlobal )

        OnPageChange record ->
            init <|
                Just
                    { path =
                        { path = record.path
                        , query = record.query
                        , fragment = record.fragment
                        }
                    , metadata = record.metadata
                    }

        MsgBlogIndex msg_ ->
            let
                ( updatedPageModel, pageCmd ) =
                    case model.page of
                        ModelBlogIndex pageModel ->
                            Template.BlogIndex.template.update (Debug.todo "")
                                msg_
                                pageModel
                                |> Tuple.mapBoth ModelBlogIndex (Cmd.map MsgBlogIndex)

                        _ ->
                            ( model.page, Cmd.none )
            in
            ( { model | page = updatedPageModel }, pageCmd )


mainTemplate { documents, manifest, canonicalSiteUrl } =
    Pages.Platform.init
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        , documents = documents
        , onPageChange = Just OnPageChange
        , manifest = manifest -- SiteConfig.manifest
        , canonicalSiteUrl = canonicalSiteUrl -- SiteConfig.canonicalUrl
        , internals = Pages.internals
        }
        |> Pages.Platform.toProgram


mapDocument : Browser.Document Never -> Browser.Document mapped
mapDocument document =
    { title = document.title
    , body = document.body |> List.map (Html.map never)
    }
`
}

module.exports = { generateTemplateModuleConnector }