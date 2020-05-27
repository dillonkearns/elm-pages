module Template.Showcase exposing (..)

import Element exposing (Element)
import Head
import Head.Seo as Seo
import Json.Decode as Decode exposing (Decoder)
import MarkdownRenderer
import Pages exposing (images)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Showcase
import Template.Metadata exposing (Showcase)


type Msg
    = Msg


decoder : Decoder Showcase
decoder =
    Decode.succeed Showcase


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    Showcase.staticRequest


type alias StaticData =
    List Showcase.Entry


init : Showcase -> Model
init metadata =
    Model


type alias Model =
    {}


type alias View msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )


view : StaticData -> Model -> Showcase -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
view data model metadata viewForPage =
    { title = "elm-pages blog"
    , body =
        Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ] [ Showcase.view data ]
            ]
    }


head : StaticData -> PagePath.PagePath Pages.PathKey -> Showcase -> List (Head.Tag Pages.PathKey)
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
        , description = "See some neat sites built using elm-pages! (Or submit yours!)"
        , locale = Nothing
        , title = "elm-pages sites showcase"
        }
        |> Seo.website
