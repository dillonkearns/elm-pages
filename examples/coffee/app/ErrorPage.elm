module ErrorPage exposing (ErrorPage(..), Model, Msg, head, init, internalError, notFound, statusCode, update, view)

import Effect exposing (Effect)
import Head
import Html
import Html.Attributes as Attr
import Route
import View exposing (View)


type Msg
    = NoOp


type alias Model =
    {}


init : ErrorPage -> ( Model, Effect Msg )
init _ =
    ( {}, Effect.none )


update : ErrorPage -> Msg -> Model -> ( Model, Effect Msg )
update _ NoOp model =
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
view error _ =
    case error of
        NotFound ->
            { body =
                [ Html.div [ Attr.class "bh-error" ]
                    [ Html.h2 [] [ Html.text "Page not found" ]
                    , Html.p []
                        [ Html.text "Let's find you a slow-pour. Check out "
                        , Route.Index |> Route.link [] [ Html.text "our menu" ]
                        , Html.text "."
                        ]
                    ]
                ]
            , title = "Page Not Found"
            }

        InternalError message ->
            { body =
                [ Html.div [ Attr.class "bh-error" ]
                    [ Html.h2 [] [ Html.text "Something went wrong" ]
                    , Html.p [] [ Html.text message ]
                    ]
                ]
            , title = "Internal Error"
            }


statusCode : ErrorPage -> number
statusCode error =
    case error of
        NotFound ->
            404

        InternalError _ ->
            500
