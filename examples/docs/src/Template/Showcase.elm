module Template.Showcase exposing (Model, Msg, decoder, template)

import Element exposing (Element)
import Head
import Head.Seo as Seo
import Json.Decode as Decode exposing (Decoder)
import Pages exposing (images)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared
import Showcase
import Template exposing (StaticPayload, Template)
import TemplateMetadata exposing (Showcase)
import TemplateType exposing (TemplateType)


type alias Model =
    ()


type alias Msg =
    Never


template : Template Showcase StaticData () Msg
template =
    Template.withStaticData
        { head = head
        , staticData = staticData
        }
        |> Template.buildNoState { view = view }


decoder : Decoder Showcase
decoder =
    Decode.succeed Showcase


staticData :
    List ( PagePath Pages.PathKey, TemplateType )
    -> StaticHttp.Request StaticData
staticData siteMetadata =
    Showcase.staticRequest


type alias StaticData =
    List Showcase.Entry


view :
    List ( PagePath Pages.PathKey, TemplateType )
    -> StaticPayload Showcase StaticData
    -> Shared.RenderedBody
    -> Shared.PageView msg
view allMetadata static rendered =
    { title = "elm-pages blog"
    , body =
        [ Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ] [ Showcase.view static.static ]
            ]
        ]
    }


head : StaticPayload Showcase StaticData -> List (Head.Tag Pages.PathKey)
head staticPayload =
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
