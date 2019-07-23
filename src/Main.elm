module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Content exposing (Content)
import Element exposing (Element)
import Element.Border
import Element.Font as Font
import Html exposing (..)
import Html.Attributes exposing (..)
import List.Extra
import Mark
import Mark.Error
import MarkParser
import Url exposing (Url)


type alias Flags =
    ()


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


type alias Model =
    { key : Nav.Key
    , url : Url.Url
    }


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( Model key url, Cmd.none )


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            ( { model | url = url }
            , Cmd.none
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> Browser.Document Msg
view model =
    { title = "URL Interceptor"
    , body =
        [ mainView model.url
            |> Element.layout
                [ Element.width Element.fill
                ]
        ]
    }


lookupPage :
    Content msg
    -> Url
    ->
        Maybe
            { body : List (Element msg)
            , metadata : MarkParser.Metadata msg
            }
lookupPage content url =
    List.Extra.find
        (\( path, markup ) ->
            (String.split "/" url.path
                |> List.drop 1
            )
                == path
        )
        (content.pages ++ content.posts)
        |> Maybe.map Tuple.second


mainView : Url -> Element msg
mainView url =
    case Content.allData of
        Ok site ->
            pageView site url

        Err errorView ->
            errorView


pageView : Content msg -> Url -> Element msg
pageView content url =
    case lookupPage content url of
        Just pageOrPost ->
            (header :: pageOrPost.body)
                |> Element.textColumn [ Element.width Element.fill ]

        Nothing ->
            Element.column []
                [ Element.text "Page not found. Valid routes:\n\n"
                , content.pages
                    |> List.map Tuple.first
                    |> List.map (String.join "/")
                    |> String.join ", "
                    |> Element.text
                ]


header =
    Element.row [ Element.padding 20, Element.Border.width 2, Element.spaceEvenly ]
        [ Element.el [ Font.size 30 ]
            (Element.link [] { url = "/", label = Element.text "elm-markup-site" })
        , Element.row [ Element.spacing 15 ]
            [ Element.link [] { url = "/articles", label = Element.text "Articles" }
            , Element.link [] { url = "/about", label = Element.text "About" }
            ]
        ]
