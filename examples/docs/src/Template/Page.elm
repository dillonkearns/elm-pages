module Template.Page exposing (Metadata, Model, Msg, decoder, head, init, staticData, view)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import Pages exposing (images)
import Pages.PagePath as PagePath
import Pages.StaticHttp as StaticHttp
import SiteConfig


type alias StaticData =
    ()


type Model
    = Model


type Msg
    = Msg


init : Metadata -> Model
init metadata =
    Model


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    StaticHttp.succeed ()


type alias Metadata =
    { title : String }


decoder : Decode.Decoder Metadata
decoder =
    Decode.map Metadata
        (Decode.field "title" Decode.string)


head : StaticData -> PagePath.PagePath Pages.PathKey -> Metadata -> List (Head.Tag Pages.PathKey)
head static currentPath meta =
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
        , title = meta.title
        }
        |> Seo.website


view : StaticData -> Model -> Metadata -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
view data model metadata viewForPage =
    { title = metadata.title
    , body =
        [ Element.column
            [ Element.padding 50
            , Element.spacing 60
            , Element.Region.mainContent
            ]
            (Tuple.second viewForPage)
        ]
            |> Element.textColumn
                [ Element.width Element.fill
                ]
    }
