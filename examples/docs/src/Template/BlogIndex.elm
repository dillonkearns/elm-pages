module Template.BlogIndex exposing (..)

import AllMetadata
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Index
import MarkdownRenderer
import Pages exposing (images)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Showcase
import SiteConfig
import Template.BlogIndexMetadata exposing (Metadata)


type Msg
    = Msg


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    Showcase.staticRequest


type alias StaticData =
    List Showcase.Entry


init : Metadata -> Model
init metadata =
    Model


type alias Model =
    {}


type alias View msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )


view : List ( PagePath Pages.PathKey, AllMetadata.Metadata ) -> StaticData -> Model -> Metadata -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
view siteMetadata data model metadata viewForPage =
    { title = "elm-pages blog"
    , body =
        Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ]
                [ siteMetadata
                    |> Index.view
                ]
            ]
    }



--{ title = "elm-pages blog"
--, body =
--    Element.column [ Element.width Element.fill ]
--        [ Element.column [ Element.padding 20, Element.centerX ] [ Showcase.view data ]
--        ]
--}


head : StaticData -> PagePath.PagePath Pages.PathKey -> Metadata -> List (Head.Tag Pages.PathKey)
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
