module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Content exposing (aboutPage)
import Element exposing (Element)
import Html exposing (..)
import Html.Attributes exposing (..)
import Mark
import Mark.Error
import MarkParser
import Url


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



-- MODEL


type alias Model =
    { key : Nav.Key
    , url : Url.Url
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( Model key url, Cmd.none )



-- UPDATE


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



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "URL Interceptor"
    , body =
        [ pageView
            |> Element.layout
                [ Element.width Element.fill

                -- , Element.explain Debug.todo
                ]
        ]
    }


pageView : Element msg
pageView =
    case Mark.compile MarkParser.document (aboutPage |> Tuple.second) of
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


viewLink : String -> Html msg
viewLink path =
    li [] [ a [ href path ] [ text path ] ]
