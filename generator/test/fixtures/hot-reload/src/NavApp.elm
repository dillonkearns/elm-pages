module NavApp exposing (main)

{-| A `Browser.application`, like the one elm-pages generates. It keeps the
navigation key in its model, which is the part of the compiled output that
hot reloading tools need to find.
-}

import Browser
import Browser.Navigation
import Html
import Url exposing (Url)


type alias Model =
    { key : Browser.Navigation.Key
    , url : Url
    }


type Msg
    = UrlRequested Browser.UrlRequest
    | UrlChanged Url


main : Program () Model Msg
main =
    Browser.application
        { init = \() url key -> ( { key = key, url = url }, Cmd.none )
        , update = update
        , view = \model -> { title = "NavApp", body = [ Html.text (Url.toString model.url) ] }
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlRequested (Browser.Internal url) ->
            ( model, Browser.Navigation.pushUrl model.key (Url.toString url) )

        UrlRequested (Browser.External href) ->
            ( model, Browser.Navigation.load href )

        UrlChanged url ->
            ( { model | url = url }, Cmd.none )
