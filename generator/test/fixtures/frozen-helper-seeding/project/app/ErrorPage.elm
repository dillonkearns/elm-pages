module ErrorPage exposing (ErrorPage(..), Model, Msg, head, init, internalError, notFound, statusCode, update, view)

import Effect exposing (Effect)
import Head
import Html.Styled as Html exposing (Html)
import View exposing (View)


type Msg
    = NoOp


type alias Model =
    {}


init : ErrorPage -> ( Model, Effect Msg )
init _ =
    ( {}
    , Effect.none
    )


update : ErrorPage -> Msg -> Model -> ( Model, Effect Msg )
update _ _ model =
    ( model, Effect.none )


head : ErrorPage -> List Head.Tag
head _ =
    []


type ErrorPage
    = NotFound
    | InternalError String


notFound : ErrorPage
notFound =
    NotFound


internalError : String -> ErrorPage
internalError =
    InternalError


view : ErrorPage -> Model -> View Msg
view error model =
    case error of
        NotFound ->
            { title = "Not Found"
            , body =
                [ Html.p [] [ Html.text "Not found." ]
                ]
            }

        InternalError message ->
            { title = "Internal Error"
            , body =
                [ Html.h2 [] [ Html.text "Something went wrong" ]
                , Html.p [] [ Html.text message ]
                ]
            }


statusCode : ErrorPage -> Int
statusCode error =
    case error of
        NotFound ->
            404

        InternalError _ ->
            500
