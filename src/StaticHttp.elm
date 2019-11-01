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
    case ( request1, request2 ) of
        ( Request ( urls1, lookupFn1 ), Request ( urls2, lookupFn2 ) ) ->
            let
                value : Dict String String -> Result String (Request c)
                value rawResponses =
                    let
                        value1 : Result String (Request a)
                        value1 =
                            lookupFn1 rawResponses

                        value2 : Result String (Request b)
                        value2 =
                            lookupFn2 rawResponses
                    in
                    Result.map2 (map2 fn) value1 value2
            in
            Request
                ( urls1 ++ urls2
                , value
                )

        ( Request ( urls1, lookupFn1 ), Done value2 ) ->
            Request
                ( urls1
                , \rawResponses ->
                    let
                        value1 : Result String (Request a)
                        value1 =
                            lookupFn1 rawResponses
                    in
                    Result.map2 (map2 fn) value1 (Ok (Done value2))
                )

        ( Done value2, Request ( urls1, lookupFn1 ) ) ->
            Request
                ( urls1
                , \rawResponses ->
                    let
                        value1 : Result String (Request b)
                        value1 =
                            lookupFn1 rawResponses
                    in
                    Result.map2 (map2 fn) (Ok (Done value2)) value1
                )

        ( Done value1, Done value2 ) ->
            fn value1 value2 |> Done


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
    succeed combine
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3


map4 :
    (value1 -> value2 -> value3 -> value4 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request valueCombined
map4 combine request1 request2 request3 request4 =
    succeed combine
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4


map5 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request valueCombined
map5 combine request1 request2 request3 request4 request5 =
    succeed combine
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5


map6 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request value6
    -> Request valueCombined
map6 combine request1 request2 request3 request4 request5 request6 =
    succeed combine
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6


map7 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request value6
    -> Request value7
    -> Request valueCombined
map7 combine request1 request2 request3 request4 request5 request6 request7 =
    succeed combine
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7


map8 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> value8 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request value6
    -> Request value7
    -> Request value8
    -> Request valueCombined
map8 combine request1 request2 request3 request4 request5 request6 request7 request8 =
    succeed combine
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7
        |> map2 (|>) request8


map9 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> value8 -> value9 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request value6
    -> Request value7
    -> Request value8
    -> Request value9
    -> Request valueCombined
map9 combine request1 request2 request3 request4 request5 request6 request7 request8 request9 =
    succeed combine
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7
        |> map2 (|>) request8
        |> map2 (|>) request9
