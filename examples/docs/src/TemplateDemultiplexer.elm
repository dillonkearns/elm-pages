module TemplateDemultiplexer exposing (..)

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
import Template.BlogIndex
import Template.BlogPost
import Template.Documentation
import Template.Page
import Template.Showcase


type alias Model =
    { global : Global.Model
    , page : TemplateModel
    }


type TemplateModel
    = ModelBlogPost Template.BlogPost.Model
    | ModelShowcase Template.Showcase.Model
    | ModelPage Template.Page.Model
    | ModelDocumentation Template.Documentation.Model
    | ModelBlogIndex Template.BlogIndex.Model


type Msg
    = MsgBlogPost Template.BlogPost.Msg
    | MsgBlogIndex Template.BlogIndex.Msg
    | MsgGlobal Global.Msg
    | OnPageChange
        { path : PagePath Pages.PathKey
        , query : Maybe String
        , fragment : Maybe String
        , metadata : Metadata
        }


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
        M.MetadataBlogPost metadata ->
            StaticHttp.map2
                (\data globalData ->
                    { view =
                        \model rendered ->
                            case model.page of
                                ModelBlogPost subModel ->
                                    Template.BlogPost.template.view
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
                    , head = Template.BlogPost.template.head data page.path metadata
                    }
                )
                (Template.BlogPost.template.staticData siteMetadata)
                (Global.staticData siteMetadata)

        M.MetadataShowcase metadata ->
            StaticHttp.map2
                (\data globalData ->
                    { view =
                        \model rendered ->
                            case model.page of
                                ModelShowcase subModel ->
                                    Template.Showcase.template.view siteMetadata data subModel metadata rendered
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
                    , head = Template.Showcase.template.head data page.path metadata
                    }
                )
                (Template.Showcase.template.staticData siteMetadata)
                (Global.staticData siteMetadata)

        M.MetadataPage metadata ->
            StaticHttp.map2
                (\data globalData ->
                    { view =
                        \model rendered ->
                            case model.page of
                                ModelPage subModel ->
                                    Template.Page.template.view siteMetadata data subModel metadata rendered
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
                    , head = Template.Page.template.head data page.path metadata
                    }
                )
                (Template.Page.template.staticData siteMetadata)
                (Global.staticData siteMetadata)

        M.MetadataBlogIndex metadata ->
            StaticHttp.map2
                (\data globalData ->
                    { view =
                        \model rendered ->
                            case model.page of
                                ModelBlogIndex subModel ->
                                    --Template.BlogIndex.view siteMetadata data subModel metadata rendered
                                    Template.BlogIndex.template.view
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
                                                    , body = Element.map never body
                                                    }
                                           )

                                _ ->
                                    { title = "", body = Html.text "" }
                    , head = Template.BlogIndex.template.head data page.path metadata
                    }
                )
                (Template.BlogIndex.template.staticData siteMetadata)
                (Global.staticData siteMetadata)

        M.MetadataDocumentation metadata ->
            StaticHttp.map2
                (\data globalData ->
                    { view =
                        \model rendered ->
                            case model.page of
                                ModelDocumentation subModel ->
                                    Template.Documentation.template.view siteMetadata data subModel metadata rendered
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
                    , head = Template.Page.template.head data page.path metadata
                    }
                )
                (Template.Page.template.staticData siteMetadata)
                (Global.staticData siteMetadata)


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

        _ ->
            ( model, Cmd.none )



-- TODO need to change Debug.todo with the page's metadata, but it's not wired through by the internals yet.
--MsgBlogIndex msg_ ->
--    let
--        ( updatedPageModel, pageCmd ) =
--            case model.page of
--                ModelBlogIndex pageModel ->
--                    Template.BlogIndex.template.update (Debug.todo "")
--                        msg_
--                        pageModel
--                        |> Tuple.mapBoth ModelBlogIndex (Cmd.map MsgBlogIndex)
--
--                _ ->
--                    ( model.page, Cmd.none )
--    in
--    ( { model | page = updatedPageModel }, pageCmd )


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
