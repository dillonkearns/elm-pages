module StaticHttp exposing (..)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder)
import Pages.Internal.Secrets
import Pages.StaticHttpRequest exposing (Request(..))
import Secrets exposing (Secrets)


type alias Request value =
    Pages.StaticHttpRequest.Request value


type alias RequestExample model rendered msg pathKey =
    Request
        { view :
            model
            -> rendered
            ->
                { title : String
                , body : Html msg
                }
        , head : List (Head.Tag pathKey)
        }


map : (a -> b) -> Request a -> Request b
map fn request =
    case request of
        Request ( urls, lookupFn ) ->
            Request
                ( urls
                , \rawResponses ->
                    lookupFn rawResponses
                        |> Result.map (map fn)
                )

        Done value ->
            fn value |> Done


map2 : (a -> b -> c) -> Request a -> Request b -> Request c
map2 fn request1 request2 =
    Request
        ( lookupUrls request1 ++ lookupUrls request2
        , \dict ->
            Result.map2 fn (lookup request1 dict) (lookup request2 dict)
                |> Result.map Done
        )


lookup : Pages.StaticHttpRequest.Request value -> Dict String String -> Result String value
lookup request rawResponses =
    case request of
        Request ( urls, lookupFn ) ->
            lookupFn rawResponses
                |> Result.andThen
                    (\nextRequest ->
                        lookup
                            (addUrls urls nextRequest)
                            rawResponses
                    )

        Done value ->
            Ok value


addUrls : List (Secrets -> Result BuildError String) -> Pages.StaticHttpRequest.Request value -> Pages.StaticHttpRequest.Request value
addUrls urlsToAdd request =
    case request of
        Request ( initialUrls, function ) ->
            Request ( initialUrls ++ urlsToAdd, function )

        Done value ->
            Done value



--            Request ( urlsToAdd, \_ -> value |> Done |> Ok )


lookupUrls : Pages.StaticHttpRequest.Request value -> List (Secrets -> Result BuildError String)
lookupUrls request =
    case request of
        Request ( urls, lookupFn ) ->
            urls

        Done value ->
            []



--type Request value
--    = Request ( List (Secrets -> Result BuildError String), Dict String String -> Result String (Request value) )
--    | Done value


andThen : (a -> Request b) -> Request a -> Request b
andThen fn request =
    Request
        ( lookupUrls request
        , \rawResponses ->
            lookup
                request
                rawResponses
                |> (\result ->
                        case result of
                            Err error ->
                                Err error

                            Ok value ->
                                fn value |> Ok
                   )
        )


succeed : a -> Request a
succeed value =
    Request ( [], \_ -> value |> Done |> Ok )


jsonRequest : String -> Decoder a -> Request a
jsonRequest url decoder =
    Request
        ( [ \secrets -> Ok url ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get url
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                Ok rawResponse

                            Nothing ->
                                --                                Ok "undefined"
                                Err <| "Couldn't find response for url `" ++ url ++ "`... available: \n[ " ++ (Dict.keys rawResponseDict |> String.join ", ") ++ " ]"
                   )
                |> Result.andThen
                    (\rawResponse ->
                        rawResponse
                            |> Decode.decodeString decoder
                            |> Result.map Done
                            |> Result.mapError Decode.errorToString
                    )
        )


jsonRequestWithSecrets : (Secrets -> Result BuildError String) -> Decoder a -> Request a
jsonRequestWithSecrets urlWithSecrets decoder =
    Request
        ( [ urlWithSecrets ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get (Pages.Internal.Secrets.useFakeSecrets urlWithSecrets)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                Ok rawResponse

                            Nothing ->
                                Err <| "Couldn't find response for url `" ++ Pages.Internal.Secrets.useFakeSecrets urlWithSecrets ++ "`"
                   )
                |> Result.andThen
                    (\rawResponse ->
                        rawResponse
                            |> Decode.decodeString decoder
                            |> Result.map Done
                            |> Result.mapError Decode.errorToString
                    )
        )


map3 :
    (value1 -> value2 -> value3 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request valueCombined
map3 combine request1 request2 request3 =
    Pages.StaticHttpRequest.Request
        ( List.concat
            [ lookupUrls request1
            , lookupUrls request2
            , lookupUrls request3
            ]
        , \dict ->
            Result.map2 combine (lookup request1 dict) (lookup request2 dict)
                |> Result.map2 (|>) (lookup request3 dict)
                |> Result.map Done
        )
