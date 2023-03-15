module ErrorPage exposing (ErrorPage(..), Model, Msg, head, init, internalError, notFound, statusCode, update, view)

import Effect exposing (Effect)
import Head
import Html.Styled as Html exposing (Html)
import View exposing (View)


type Msg
    = Increment


type alias Model =
    { count : Int
    }


init : ErrorPage -> ( Model, Effect Msg )
init errorPage =
    ( { count = 0 }
    , Effect.none
    )


update : ErrorPage -> Msg -> Model -> ( Model, Effect Msg )
update errorPage msg model =
    case msg of
        Increment ->
            ( { model | count = model.count + 1 }, Effect.none )


head : ErrorPage -> List Head.Tag
head errorPage =
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
            { title = "This is a NotFound Error"
            , body =
                [ Html.div []
                    [ Html.p [] [ Html.text "Page not found. Maybe try another URL?" ]
                    ]
                ]
            }

        InternalError string ->
            { title = "This is a NotFound Error"
            , body =
                [ Html.h2 []
                    [ Html.text "Something's Not Right Here"
                    ]
                , Html.div []
                    [ Html.p [] [ Html.text string ]
                    ]
                ]
            }


statusCode : ErrorPage -> number
statusCode error =
    case error of
        NotFound ->
            404

        InternalError _ ->
            500
