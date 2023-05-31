module ErrorPage exposing (ErrorPage(..), Model, Msg, head, init, internalError, notFound, statusCode, update, view)

import Effect exposing (Effect)
import Head
import Html exposing (Html)
import Html.Events exposing (onClick)
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
    | InvalidPokedexNumber String
    | MissingPokedexNumber Int
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
        InvalidPokedexNumber invalidNumber ->
            { body =
                [ Html.div []
                    [ Html.p []
                        [ Html.text ("`" ++ invalidNumber ++ "`" ++ " doesn't look like a pokedex number. Make sure it's a valid number, like ")
                        , Route.PokedexNumber_ { pokedexNumber = "25" } |> Route.link [] [ Html.text "25" ]
                        , Html.text "."
                        ]
                    , Html.div []
                        [ Html.button
                            [ onClick Increment
                            ]
                            [ Html.text
                                (model.count
                                    |> String.fromInt
                                )
                            ]
                        ]
                    ]
                ]
            , title = "Invalid pokedex number"
            }

        MissingPokedexNumber missingNumber ->
            { body =
                [ Html.div []
                    [ Html.p []
                        [ Html.text ("`" ++ String.fromInt missingNumber ++ "`" ++ " isn't in our pokedex. This pokemon is pretty cute, though: ")
                        , Route.PokedexNumber_ { pokedexNumber = "25" } |> Route.link [] [ Html.text "#25" ]
                        , Html.text "."
                        ]
                    , Html.div []
                        [ Html.button
                            [ onClick Increment
                            ]
                            [ Html.text
                                (model.count
                                    |> String.fromInt
                                )
                            ]
                        ]
                    ]
                ]
            , title = "Invalid pokedex number"
            }

        NotFound ->
            { body =
                [ Html.div []
                    [ Html.p [] [ Html.text "Page not found. Maybe try another URL?" ]
                    , Html.div []
                        [ Html.button
                            [ onClick Increment
                            ]
                            [ Html.text
                                (model.count
                                    |> String.fromInt
                                )
                            ]
                        ]
                    ]
                ]
            , title = "This is a NotFound Error"
            }

        InternalError errorMessage ->
            { body =
                [ Html.div []
                    [ Html.h2 [] [ Html.text "Something's Not Right Here" ]
                    , Html.p [] [ Html.text errorMessage ]
                    ]
                ]
            , title = "Internal Server Error"
            }


statusCode : ErrorPage -> number
statusCode error =
    case error of
        NotFound ->
            404

        InternalError _ ->
            500

        InvalidPokedexNumber _ ->
            400

        MissingPokedexNumber _ ->
            404
