module Template.Page exposing (Model, Msg, decoder, head, init, staticData, template, view)

import Element exposing (Element)
import Element.Region
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import Pages exposing (images)
import Pages.PagePath as PagePath
import Pages.StaticHttp as StaticHttp
import SiteConfig
import Template
import Template.Metadata exposing (Page)
import TemplateDocument exposing (TemplateDocument)


type alias StaticData =
    ()


type Model
    = Model


type Msg
    = Msg


template : TemplateDocument Page StaticData Model Msg
template =
    Template.template
        { view = view
        , head = head
        , staticData = staticData
        , init = init
        , update = update
        }


init : Page -> ( Model, Cmd Msg )
init metadata =
    ( Model, Cmd.none )


update : Page -> Msg -> Model -> ( Model, Cmd Msg )
update metadata msg model =
    ( Model, Cmd.none )


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    StaticHttp.succeed ()


decoder : Decode.Decoder Page
decoder =
    Decode.map Page
        (Decode.field "title" Decode.string)


head : StaticData -> PagePath.PagePath Pages.PathKey -> Page -> List (Head.Tag Pages.PathKey)
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


view : StaticData -> Model -> Page -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
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
