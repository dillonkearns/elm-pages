module ErrorPage exposing (ErrorPage(..), Model, Msg, head, init, internalError, notFound, statusCode, update, view)

import Effect exposing (Effect)
import Head
import Html exposing (Html)
import Html.Attributes as Attr
import Route
import View exposing (View)
import View.Coffee


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
                [ headerShell
                , errorHero
                    { code = "404"
                    , eyebrow = "Off the menu"
                    , title = "We couldn't find that page."
                    , body = "Let's get you back to a slow-pour. Browse the bar, or wander back to the front door."
                    }
                ]
            , title = "Page not found · Blendhaus"
            }

        InternalError message ->
            { body =
                [ headerShell
                , errorHero
                    { code = "500"
                    , eyebrow = "Espresso machine down"
                    , title = "Something went wrong."
                    , body = message
                    }
                ]
            , title = "Internal error · Blendhaus"
            }


headerShell : Html msg
headerShell =
    View.Coffee.shell
        { greeting = Nothing
        , signoutForm = Nothing
        , cartCount = 0
        }


errorHero :
    { code : String
    , eyebrow : String
    , title : String
    , body : String
    }
    -> Html msg
errorHero { code, eyebrow, title, body } =
    Html.section [ Attr.class "bh-error" ]
        [ Html.h1 [ Attr.class "bh-error-code" ]
            (case String.toList code of
                [ a, b, c ] ->
                    [ Html.text (String.fromChar a)
                    , Html.em [] [ Html.text (String.fromChar b) ]
                    , Html.text (String.fromChar c)
                    ]

                _ ->
                    [ Html.text code ]
            )
        , Html.div [ Attr.class "bh-error-meta" ]
            [ Html.span [ Attr.class "bh-error-eyebrow" ] [ Html.text eyebrow ]
            , Html.h2 [ Attr.class "bh-error-title" ] [ Html.text title ]
            , Html.p [ Attr.class "bh-error-body" ] [ Html.text body ]
            , Html.div [ Attr.class "bh-error-actions" ]
                [ Route.Index
                    |> Route.link [ Attr.class "bh-error-back" ]
                        [ Html.span [] [ Html.text "Back to the menu" ]
                        , Html.span [ Attr.class "arr" ] [ Html.text "→" ]
                        ]
                ]
            ]
        ]


statusCode : ErrorPage -> number
statusCode error =
    case error of
        NotFound ->
            404

        InternalError _ ->
            500
