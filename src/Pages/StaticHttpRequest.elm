module Pages.StaticHttpRequest exposing (Request(..), parser)

import Head
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder)
import Pages.PagePath exposing (PagePath)


type Request value
    = Request
        { parser : String -> value
        , url : String
        }


type Request2
    = Request2 { url : String }


withoutData :
    { view :
        model
        -> rendered
        ->
            { title : String
            , body : Html msg
            }
    , head : List (Head.Tag pathKey)
    }
    ->
        ( Request2
        , String
          ->
            Result String
                { view :
                    model
                    -> rendered
                    ->
                        { title : String
                        , body : Html msg
                        }
                , head : List (Head.Tag pathKey)
                }
        )
withoutData buildFns =
    ( Request2 { url = "" }
    , \stringData ->
        buildFns
            |> Ok
    )


tryWith page =
    if page == 1 then
        withData "https://api.github.com/123"
            Decode.int
            (\staticData ->
                { view =
                    \model rendered ->
                        { title = "My title"
                        , body = Html.text <| "Data is: " ++ String.fromInt staticData
                        }
                , head = []
                }
            )

    else if page == 2 then
        withData "https://api.github.com/123"
            Decode.string
            (\staticData ->
                { view =
                    \model rendered ->
                        { title = "My title"
                        , body = Html.text <| "Data is: " ++ staticData
                        }
                , head = []
                }
            )

    else
        withoutData
            { view =
                \model rendered ->
                    { title = "My title"
                    , body = Html.text <| "There's no data here."
                    }
            , head = []
            }


withData :
    String
    -> Decoder staticData
    ->
        (staticData
         ->
            { view :
                model
                -> rendered
                ->
                    { title : String
                    , body : Html msg
                    }
            , head : List (Head.Tag pathKey)
            }
        )
    ->
        ( Request2
        , String
          ->
            Result String
                { view :
                    model
                    -> rendered
                    ->
                        { title : String
                        , body : Html msg
                        }
                , head : List (Head.Tag pathKey)
                }
        )
withData url decoder buildFns =
    ( Request2 { url = url }
    , \stringData ->
        case stringData |> Decode.decodeString decoder of
            Ok staticData ->
                buildFns staticData
                    |> Ok

            Err error ->
                Err (Decode.errorToString error)
    )


type alias Thing rendered pathKey metadata model msg =
    List ( PagePath pathKey, metadata )
    ->
        { path : PagePath pathKey
        , frontmatter : metadata
        }
    ->
        ( Request2
        , String
          ->
            Result String
                { view :
                    model
                    -> rendered
                    ->
                        { title : String
                        , body : Html msg
                        }
                , head : List (Head.Tag pathKey)
                }
        )


parser : Request value -> (String -> value)
parser (Request request) =
    request.parser
