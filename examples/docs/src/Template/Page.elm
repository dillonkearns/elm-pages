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
import Template exposing (StaticPayload, Template)
import TemplateMetadata exposing (Page)


type alias StaticData =
    ()


type alias Model =
    ()


type Msg
    = Msg


template : Template Page () () Msg
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


head : StaticPayload Page () -> List (Head.Tag Pages.PathKey)
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
        , description = SiteConfig.tagline
        , locale = Nothing
        , title = staticPayload.metadata.title
        }
        |> Seo.website


view :
    List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
    -> StaticPayload Page ()
    -> Global.RenderedBody
    -> { title : String, body : Element Msg }
view allMetadata staticPayload rendered =
    { title = staticPayload.metadata.title
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
