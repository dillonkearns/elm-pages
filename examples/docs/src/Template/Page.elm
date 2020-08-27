module Template.Page exposing (Model, Msg, decoder, template)

import Element exposing (Element)
import Element.Region
import Global
import GlobalMetadata
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import Pages exposing (images)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import SiteConfig
import Template
import TemplateDocument exposing (TemplateDocument)
import TemplateMetadata exposing (Page)


type alias StaticData =
    ()


type alias Model =
    ()


type Msg
    = Msg


template : TemplateDocument Page StaticData Model Msg msg
template =
    Template.simplest
        { view = view
        , head = head
        }


init : Page -> ( Model, Cmd Msg )
init metadata =
    ( (), Cmd.none )


update : Page -> Msg -> Model -> ( Model, Cmd Msg )
update metadata msg model =
    ( (), Cmd.none )


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    StaticHttp.succeed ()


decoder : Decode.Decoder Page
decoder =
    Decode.map Page
        (Decode.field "title" Decode.string)


head : PagePath.PagePath Pages.PathKey -> Page -> List (Head.Tag Pages.PathKey)
head currentPath meta =
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


view :
    (Msg -> msg)
    -> (Global.Msg -> msg)
    -> List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
    -> Model
    -> Page
    -> Global.RenderedBody Never
    -> { title : String, body : Element Never }
view toMsg toGlobalMsg allMetadata model metadata rendered =
    { title = metadata.title
    , body =
        [ Element.column
            [ Element.padding 50
            , Element.spacing 60
            , Element.Region.mainContent
            ]
            (Tuple.second rendered)
        ]
            |> Element.textColumn
                [ Element.width Element.fill
                ]
    }
