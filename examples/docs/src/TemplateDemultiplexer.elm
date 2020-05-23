module TemplateDemultiplexer exposing (..)

import Element exposing (Element)
import Global
import Head
import Html exposing (Html)
import MarkdownRenderer
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Template.BlogPost
import Template.Showcase


type Metadata
    = MetadataBlogPost Template.BlogPost.Metadata
    | MetadataShowcase Template.Showcase.Metadata


type alias Model =
    { global : Global.Model
    , page : TemplateModel
    }


type TemplateModel
    = ModelBlogPost Template.BlogPost.Model
    | ModelShowcase Template.Showcase.Model


type Msg
    = MsgBlogPost Template.BlogPost.Msg


type alias View =
    ( MarkdownRenderer.TableOfContents, List (Element Msg) )


toView =
    Debug.todo ""


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
        MetadataBlogPost metadata ->
            StaticHttp.map2
                (\data globalData ->
                    { view =
                        \model rendered ->
                            case model.page of
                                ModelBlogPost subModel ->
                                    Template.BlogPost.view data subModel metadata rendered
                                        |> (\{ title, body } ->
                                                Global.wrapBody
                                                    globalData
                                                    page
                                                    model.global
                                                    liftGlobalMsg
                                                    { title = title
                                                    , body =
                                                        -- Template.BlogPost.liftViewMsg
                                                        body
                                                    }
                                           )

                                _ ->
                                    { title = "", body = Html.text "" }
                    , head = Template.BlogPost.head data page.path metadata
                    }
                )
                (Template.BlogPost.staticData siteMetadata)
                (Global.staticData siteMetadata)

        MetadataShowcase metadata ->
            Debug.todo ""


liftGlobalMsg =
    Debug.todo ""
