module Template.Page exposing (Model, Msg, decoder, template)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import OptimizedDecoder
import Pages exposing (images)
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Secrets
import Shared
import Site
import Template exposing (StaticPayload, Template, TemplateWithState)
import TemplateMetadata exposing (Page)
import TemplateType exposing (TemplateType)


type alias Model =
    ()


type alias Msg =
    Never


type alias StaticData =
    String


template : Template Page StaticData
template =
    Template.withStaticData
        { head = head
        , staticData =
            \_ ->
                StaticHttp.get (Secrets.succeed "http://worldtimeapi.org/api/timezone/America/Los_Angeles")
                    (OptimizedDecoder.field "datetime" OptimizedDecoder.string)
        }
        |> Template.buildNoState { view = view }


decoder : Decode.Decoder Page
decoder =
    Decode.map Page
        (Decode.field "title" Decode.string)


head :
    StaticPayload Page StaticData
    -> List (Head.Tag Pages.PathKey)
head { metadata } =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = Site.tagline
        , locale = Nothing
        , title = metadata.title
        }
        |> Seo.website


view :
    List ( PagePath Pages.PathKey, TemplateType )
    -> StaticPayload Page StaticData
    -> Shared.RenderedBody
    -> Shared.PageView msg
view allMetadata static rendered =
    { title = static.metadata.title
    , body =
        [ Element.text static.static
            |> Element.el [ Element.padding 40 ]
        ]
    }
