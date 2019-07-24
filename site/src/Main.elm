module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Content exposing (Content)
import Element exposing (Element)
import Element.Border
import Element.Font as Font
import List.Extra
import Mark
import Mark.Error
import MarkParser
import RawContent
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
    let
        { title, body } =
            mainView model.url
    in
    { title = title
    , body =
        [ body
            |> Element.layout
                [ Element.width Element.fill
                ]
        ]
    }


mainView : Url -> { title : String, body : Element msg }
mainView url =
    case RawContent.content of
        Ok site ->
            pageView site url

        Err errorView ->
            { title = "Error parsing"
            , body = errorView
            }


pageView : Content msg -> Url -> { title : String, body : Element msg }
pageView content url =
    case Content.lookup content url of
        Just pageOrPost ->
            { title = pageOrPost.metadata.title.raw
            , body =
                (header :: pageOrPost.body)
                    |> Element.textColumn [ Element.width Element.fill ]
            }

        Nothing ->
            { title = "Page not found"
            , body =
                Element.column []
                    [ Element.text "Page not found. Valid routes:\n\n"
                    , (content.pages ++ content.posts)
                        |> List.map Tuple.first
                        |> List.map (String.join "/")
                        |> String.join ", "
                        |> Element.text
                    ]
            }


header : Element msg
header =
    Element.row [ Element.padding 20, Element.Border.width 2, Element.spaceEvenly ]
        [ Element.el [ Font.size 30 ]
            (Element.link [] { url = "/", label = Element.text "elm-markup-site" })
        , Element.row [ Element.spacing 15 ]
            [ Element.link [] { url = "/articles", label = Element.text "Articles" }
            , Element.link [] { url = "/about", label = Element.text "About" }
            ]
        ]
