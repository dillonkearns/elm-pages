module StaticHttp exposing
    ( Request
    , jsonRequest, jsonRequestWithSecrets, reducedJsonRequest
    , map, succeed
    , andThen
    , map2, map3, map4, map5, map6, map7, map8, map9
    )

{-| TODO

@docs Request
@docs jsonRequest, jsonRequestWithSecrets, reducedJsonRequest
@docs map, succeed

@docs andThen

@docs map2, map3, map4, map5, map6, map7, map8, map9

-}

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Exploration
import Pages.Internal.Secrets
import Pages.StaticHttpRequest exposing (Request(..))
import Secrets exposing (Secrets)


{-| TODO
-}
type alias Request value =
    Pages.StaticHttpRequest.Request value


{-| TODO
-}
map : (a -> b) -> Request a -> Request b
map fn request =
    case request of
        Request ( urls, lookupFn ) ->
            Request
                ( urls
                , \rawResponses ->
                    lookupFn rawResponses
                        |> Result.map (\( partiallyStripped, nextRequest ) -> ( partiallyStripped, map fn nextRequest ))
                )

        Done value ->
            fn value |> Done


{-| TODO
-}
map2 : (a -> b -> c) -> Request a -> Request b -> Request c
map2 fn request1 request2 =
    case ( request1, request2 ) of
        ( Request ( urls1, lookupFn1 ), Request ( urls2, lookupFn2 ) ) ->
            let
                value : Dict String String -> Result Pages.StaticHttpRequest.Error ( Dict String String, Request c )
                value rawResponses =
                    let
                        value1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.second

                        value2 =
                            lookupFn2 rawResponses
                                |> Result.map Tuple.second

                        dict1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.first

                        dict2 =
                            lookupFn2 rawResponses
                                |> Result.map Tuple.first
                    in
                    Result.map2
                        (\thing1 thing2 ->
                            -- @@@@@@@@@@ TODO combine the two dicts here
                            ( rawResponses, map2 fn thing1 thing2 )
                        )
                        value1
                        value2
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
                        value1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.second
                    in
                    --                    Result.map2 (map2 fn) value1 (Ok (Done value2))
                    Result.map2
                        (\thing1 thing2 ->
                            -- @@@@@@@@@@ TODO combine the two dicts here
                            ( rawResponses, map2 fn thing1 thing2 )
                        )
                        value1
                        (Ok (Done value2))
                )

        ( Done value2, Request ( urls1, lookupFn1 ) ) ->
            Request
                ( urls1
                , \rawResponses ->
                    let
                        value1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.second
                    in
                    --                    Result.map2 (map2 fn) (Ok (Done value2)) value1
                    Result.map2
                        (\thing1 thing2 ->
                            -- @@@@@@@@@@ TODO combine the two dicts here
                            ( rawResponses, map2 fn thing1 thing2 )
                        )
                        (Ok (Done value2))
                        value1
                )

        ( Done value1, Done value2 ) ->
            fn value1 value2 |> Done


lookup : Pages.StaticHttpRequest.Request value -> Dict String String -> Result Pages.StaticHttpRequest.Error value
lookup request rawResponses =
    case request of
        Request ( urls, lookupFn ) ->
            lookupFn rawResponses
                |> Result.andThen
                    (\( strippedResponses, nextRequest ) ->
                        lookup
                            (addUrls urls nextRequest)
                            rawResponses
                    )

        Done value ->
            Ok value


addUrls : List Pages.Internal.Secrets.UrlWithSecrets -> Pages.StaticHttpRequest.Request value -> Pages.StaticHttpRequest.Request value
addUrls urlsToAdd request =
    case request of
        Request ( initialUrls, function ) ->
            Request ( initialUrls ++ urlsToAdd, function )

        Done value ->
            Done value



--            Request ( urlsToAdd, \_ -> value |> Done |> Ok )


lookupUrls : Pages.StaticHttpRequest.Request value -> List Pages.Internal.Secrets.UrlWithSecrets
lookupUrls request =
    case request of
        Request ( urls, lookupFn ) ->
            urls

        Done value ->
            []


{-| TODO
-}
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
                                ( rawResponses, fn value ) |> Ok
                   )
        )


{-| TODO
-}
succeed : a -> Request a
succeed value =
    Request
        ( []
        , \rawResponses ->
            Ok ( rawResponses, Done value )
        )


{-| TODO
-}
jsonRequest : String -> Decoder a -> Request a
jsonRequest url decoder =
    Request
        ( [ Pages.Internal.Secrets.urlWithoutSecrets url ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get url
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                -- @@@@@ TODO reduce raw responses
                                Ok
                                    ( rawResponseDict
                                    , rawResponse
                                    )

                            Nothing ->
                                Err <| Pages.StaticHttpRequest.MissingHttpResponse url
                   )
                |> Result.andThen
                    (\( strippedResponses, rawResponse ) ->
                        rawResponse
                            |> Decode.decodeString decoder
                            |> Result.mapError Decode.errorToString
                            |> Result.mapError Pages.StaticHttpRequest.DecoderError
                            |> Result.map Done
                            |> Result.map (\finalRequest -> ( strippedResponses, finalRequest ))
                    )
        )


{-| TODO
-}
reducedJsonRequest : String -> Json.Decode.Exploration.Decoder a -> Request a
reducedJsonRequest url decoder =
    Request
        ( [ Pages.Internal.Secrets.urlWithoutSecrets url ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get url
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                -- @@@@@ TODO reduce raw responses
                                Ok
                                    ( rawResponseDict
                                      --                                        |> Dict.update url (\maybeValue -> Just """{"fake": 123}""")
                                    , rawResponse
                                    )

                            Nothing ->
                                Err <| Pages.StaticHttpRequest.MissingHttpResponse url
                   )
                |> Result.andThen
                    (\( strippedResponses, rawResponse ) ->
                        let
                            reduced =
                                Json.Decode.Exploration.stripString decoder rawResponse
                                    |> Result.withDefault "TODO"
                        in
                        rawResponse
                            |> Json.Decode.Exploration.decodeString decoder
                            --                                                        |> Result.mapError Json.Decode.Exploration.errorsToString
                            |> (\decodeResult ->
                                    case decodeResult of
                                        Json.Decode.Exploration.BadJson ->
                                            Pages.StaticHttpRequest.DecoderError "" |> Err

                                        Json.Decode.Exploration.Errors errors ->
                                            Pages.StaticHttpRequest.DecoderError "" |> Err

                                        Json.Decode.Exploration.WithWarnings warnings a ->
                                            --                                            Pages.StaticHttpRequest.DecoderError "" |> Err
                                            Ok a

                                        Json.Decode.Exploration.Success a ->
                                            Ok a
                               )
                            --                            |> Result.mapError Pages.StaticHttpRequest.DecoderError
                            |> Result.map Done
                            |> Result.map (\finalRequest -> ( strippedResponses |> Dict.insert url reduced, finalRequest ))
                    )
        )


{-| TODO
-}
jsonRequestWithSecrets : (Secrets -> Result BuildError String) -> Decoder a -> Request a
jsonRequestWithSecrets urlWithSecrets decoder =
    Request
        ( [ Pages.Internal.Secrets.stringToUrl urlWithSecrets
          ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get (Pages.Internal.Secrets.useFakeSecrets2 urlWithSecrets)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                -- @@@@@ TODO reduce raw responses
                                Ok ( rawResponseDict, rawResponse )

                            Nothing ->
                                --                                Err <| "Couldn't find response for url `" ++ Pages.Internal.Secrets.useFakeSecrets urlWithSecrets ++ "`"
                                Err <| Pages.StaticHttpRequest.MissingHttpResponse <| Pages.Internal.Secrets.useFakeSecrets2 urlWithSecrets
                   )
                |> Result.andThen
                    (\( strippedResponses, rawResponse ) ->
                        rawResponse
                            |> Decode.decodeString decoder
                            |> Result.mapError Decode.errorToString
                            |> Result.mapError Pages.StaticHttpRequest.DecoderError
                            |> Result.map Done
                            |> Result.map (\finalRequest -> ( strippedResponses, finalRequest ))
                    )
        )


{-| TODO
-}
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


{-| TODO
-}
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


{-| TODO
-}
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


{-| TODO
-}
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


{-| TODO
-}
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


{-| TODO
-}
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


{-| TODO
-}
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
