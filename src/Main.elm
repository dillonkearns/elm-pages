module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Content exposing (aboutPage)
import Element exposing (Element)
import Html exposing (..)
import Html.Attributes exposing (..)
import List.Extra
import Mark
import Mark.Error
import MarkParser
import Url exposing (Url)


main : Program () Model Msg
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


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
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


lookupPage : Url -> Maybe String
lookupPage url =
    List.Extra.find
        (\( path, markup ) ->
            (String.split "/" url.path
                |> List.drop 1
                |> Debug.log "left"
            )
                == (path |> Debug.log "right")
        )
        Content.pages
        |> Maybe.map Tuple.second


indexView : Element msg
indexView =
    case Content.posts of
        Ok posts ->
            Element.column []
                [ Element.text "index"
                , Element.column []
                    (posts
                        |> List.map postSummary
                    )
                ]

        Err markupErrors ->
            Element.column []
                (markupErrors
                    |> List.map (Mark.Error.toHtml Mark.Error.Light)
                    |> List.map Element.html
                )


postSummary : ( String, MarkParser.Metadata msg ) -> Element msg
postSummary ( string, metadata ) =
    Element.paragraph [] metadata.title


mainView : Url -> Element msg
mainView url =
    if url.path == "/articles" then
        indexView

    else
        pageView url


pageView : Url -> Element msg
pageView url =
    case lookupPage url of
        Just page ->
            case Mark.compile MarkParser.document page of
                Mark.Success markup ->
                    markup.body
                        |> Element.textColumn [ Element.width Element.fill ]

                Mark.Almost { errors, result } ->
                    errors
                        |> List.map (Mark.Error.toHtml Mark.Error.Light)
                        |> List.map Element.html
                        |> Element.column []

                Mark.Failure errors ->
                    errors
                        |> List.map (Mark.Error.toHtml Mark.Error.Light)
                        |> List.map Element.html
                        |> Element.column []

        Nothing ->
            Element.text "Page not found..."
