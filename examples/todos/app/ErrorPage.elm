module ErrorPage exposing (ErrorPage(..), Model, Msg, head, init, internalError, notFound, statusCode, update, view)

import Effect exposing (Effect)
import Head
import Html
import Route
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
        _ ->
            { body =
                [ Html.div []
                    [ Html.p []
                        [ Html.text "Let's find you a nice refreshing smoothie. Check out "
                        , Route.Visibility__ { visibility = Nothing } |> Route.link [] [ Html.text "our menu" ]
                        ]
                    , Html.div [] []
                    ]
                ]
            , title = "This is a NotFound Error"
            }


statusCode : ErrorPage -> number
statusCode error =
    case error of
        NotFound ->
            404

        InternalError _ ->
            500
