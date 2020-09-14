module Template.Page exposing (Model, Msg, decoder, template)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import Pages exposing (images)
import Pages.PagePath exposing (PagePath)
import Shared
import Site
import Template exposing (StaticPayload, Template)
import TemplateMetadata exposing (Page)


type alias Model =
    ()


type alias Msg =
    Never


template : Template.TemplateSandbox Page
template =
    Template.sandbox
        { view = view
        , head = head
        }


decoder : Decode.Decoder Page
decoder =
    Decode.map Page
        (Decode.field "title" Decode.string)


head :
    Page
    -> PagePath Pages.PathKey
    -> List (Head.Tag Pages.PathKey)
head metadata path =
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
    Page
    -> PagePath Pages.PathKey
    -> Shared.RenderedBody
    -> Shared.PageView msg
view metadata path rendered =
    { title = metadata.title
    , body =
        [ Element.column
            [ Element.padding 50
            , Element.spacing 60
            , Element.Region.mainContent
            ]
            (Tuple.second rendered |> List.map (Element.map never))
        ]
            |> Element.textColumn
                [ Element.width Element.fill
                ]
    }
