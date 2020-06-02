module Template.BlogIndex exposing (..)

import Element exposing (Element)
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
import Template.Metadata exposing (BlogIndex)
import TemplateDocument exposing (TemplateDocument)


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


update : BlogIndex -> Msg -> Model -> ( Model, Cmd Msg )
update metadata msg model =
    ( Model, Cmd.none )


type alias Model =
    {}


type alias View msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )



--view : List ( PagePath Pages.PathKey, GlobalMetadata.Metadata ) -> StaticData -> Model -> BlogIndex -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
--view siteMetadata data model metadata viewForPage =


view : StaticData -> Model -> BlogIndex -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
view data model metadata viewForPage =
    { title = "elm-pages blog"
    , body =
        Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ]
                [ --siteMetadata
                  []
                    |> Index.view
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
