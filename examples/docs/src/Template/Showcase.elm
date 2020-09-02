module Template.Showcase exposing (Model, Msg, decoder, template)

import Element exposing (Element)
import Global
import GlobalMetadata
import Head
import Head.Seo as Seo
import Json.Decode as Decode exposing (Decoder)
import Pages exposing (images)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Showcase
import Template
import TemplateDocument exposing (TemplateDocument)
import TemplateMetadata exposing (Showcase)


type alias Model =
    ()


type Msg
    = Msg


template : TemplateDocument Showcase StaticData Model Msg
template =
    Template.stateless
        { view = view
        , head = head
        , staticData = staticData
        }


decoder : Decoder Showcase
decoder =
    Decode.succeed Showcase


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    Showcase.staticRequest


type alias StaticData =
    List Showcase.Entry


view :
    List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
    -> StaticData
    -> Showcase
    -> Global.RenderedBody
    -> { title : String, body : Element Msg }
view allMetadata static metadata rendered =
    { title = "elm-pages blog"
    , body =
        Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ] [ Showcase.view static ]
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
