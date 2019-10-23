module Pages.StaticHttp exposing
    ( withData, withoutData
    , Request
    )

{-| TODO

@docs withData, withoutData

@docs Request

-}

import Head
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder)
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttpRequest exposing (Request(..))


{-| TODO
-}
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
        ( Request
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
    ( Request { url = "" }
    , \stringData ->
        buildFns
            |> Ok
    )


{-| TODO
-}
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
        ( Request
        , Decode.Value
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
    ( Request { url = url }
    , \stringData ->
        case stringData |> Decode.decodeValue decoder of
            Ok staticData ->
                buildFns staticData
                    |> Ok

            Err error ->
                Err (Decode.errorToString error)
    )


{-| TODO
-}
type alias Request =
    Pages.StaticHttpRequest.Request
