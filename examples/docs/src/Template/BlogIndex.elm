module Template.BlogIndex exposing (Model, Msg, template)

import Element exposing (Element)
import Global
import GlobalMetadata
import Head
import Head.Seo as Seo
import Index
import MarkdownRenderer
import Pages exposing (images)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Showcase
import SiteConfig
import Template
import TemplateDocument exposing (TemplateDocument)
import TemplateMetadata exposing (BlogIndex)


type Msg
    = Msg


template : TemplateDocument BlogIndex StaticData Model Msg
template =
    Template.template
        { view = view
        , head = head
        , staticData = staticData
        , init = init
        , update = update
        }


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    Showcase.staticRequest


type alias StaticData =
    List Showcase.Entry


init : BlogIndex -> ( Model, Cmd msg )
init metadata =
    ( Model, Cmd.none )


update : BlogIndex -> Msg -> Model -> ( Model, Cmd Msg, Global.GlobalMsg )
update metadata msg model =
    ( Model, Cmd.none, Global.NoOp )


type alias Model =
    {}


type alias View msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )



--view : List ( PagePath Pages.PathKey, GlobalMetadata.Metadata ) -> StaticData -> Model -> BlogIndex -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
--view siteMetadata data model metadata viewForPage =


view :
    Global.Model
    -> List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
    -> StaticData
    -> Model
    -> BlogIndex
    -> Global.RenderedBody
    -> { title : String, body : Element Msg }
view globalModel allMetadata static model metadata rendered =
    { title = "elm-pages blog"
    , body =
        Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ]
                [ Index.view allMetadata
                ]
            ]
    }


head : StaticData -> PagePath.PagePath Pages.PathKey -> BlogIndex -> List (Head.Tag Pages.PathKey)
head static currentPath metadata =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = SiteConfig.tagline
        , locale = Nothing
        , title = "elm-pages blog"
        }
        |> Seo.website
