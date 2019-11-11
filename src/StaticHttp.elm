module StaticHttp exposing
    ( Request
    , get, getWithSecrets, reducedGet, reducedPost, request
    , jsonRequest, jsonRequestWithSecrets, reducedJsonRequest
    , map, succeed
    , andThen
    , map2, map3, map4, map5, map6, map7, map8, map9
    )

{-| TODO

@docs Request
@docs get, getWithSecrets, reducedGet, reducedPost, request
@docs jsonRequest, jsonRequestWithSecrets, reducedJsonRequest
@docs map, succeed

@docs andThen

@docs map2, map3, map4, map5, map6, map7, map8, map9

-}

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Dict.Extra
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Exploration
import Pages.Internal.Secrets
import Pages.StaticHttpRequest exposing (Request(..))
import Secrets2


{-| TODO
-}
type alias Request value =
    Pages.StaticHttpRequest.Request value


{-| TODO
-}
map : (a -> b) -> Request a -> Request b
map fn requestInfo =
    case requestInfo of
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
                                |> Result.withDefault Dict.empty

                        dict2 =
                            lookupFn2 rawResponses
                                |> Result.map Tuple.first
                                |> Result.withDefault Dict.empty
                    in
                    Result.map2
                        (\thing1 thing2 ->
                            ( combineReducedDicts dict1 dict2, map2 fn thing1 thing2 )
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

                        dict1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.first
                                |> Result.withDefault Dict.empty
                    in
                    Result.map2
                        (\thing1 thing2 ->
                            ( dict1, map2 fn thing1 thing2 )
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

                        dict1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.first
                                |> Result.withDefault Dict.empty
                    in
                    Result.map2
                        (\thing1 thing2 ->
                            ( dict1, map2 fn thing1 thing2 )
                        )
                        (Ok (Done value2))
                        value1
                )

        ( Done value1, Done value2 ) ->
            fn value1 value2 |> Done


{-| Takes two dicts representing responses, some of which have been reduced, and picks the shorter of the two.
This is assuming that there are no duplicate URLs, so it can safely choose between either a raw or a reduced response.
It would not work correctly if it chose between two responses that were reduced with different `Json.Decode.Exploration.Decoder`s.
-}
combineReducedDicts : Dict String String -> Dict String String -> Dict String String
combineReducedDicts dict1 dict2 =
    (Dict.toList dict1 ++ Dict.toList dict2)
        |> Dict.Extra.fromListDedupe
            (\response1 response2 ->
                if String.length response1 < String.length response2 then
                    response1

                else
                    response2
            )


lookup : Pages.StaticHttpRequest.Request value -> Dict String String -> Result Pages.StaticHttpRequest.Error ( Dict String String, value )
lookup requestInfo rawResponses =
    case requestInfo of
        Request ( urls, lookupFn ) ->
            lookupFn rawResponses
                |> Result.andThen
                    (\( strippedResponses, nextRequest ) ->
                        lookup
                            (addUrls urls nextRequest)
                            strippedResponses
                    )

        Done value ->
            Ok ( rawResponses, value )


addUrls : List (Secrets2.Value { url : String, method : String }) -> Pages.StaticHttpRequest.Request value -> Pages.StaticHttpRequest.Request value
addUrls urlsToAdd requestInfo =
    case requestInfo of
        Request ( initialUrls, function ) ->
            Request ( initialUrls ++ urlsToAdd, function )

        Done value ->
            Done value



--            Request ( urlsToAdd, \_ -> value |> Done |> Ok )


lookupUrls : Pages.StaticHttpRequest.Request value -> List (Secrets2.Value { url : String, method : String })
lookupUrls requestInfo =
    case requestInfo of
        Request ( urls, lookupFn ) ->
            urls

        Done value ->
            []


{-| TODO
-}
andThen : (a -> Request b) -> Request a -> Request b
andThen fn requestInfo =
    Request
        ( lookupUrls requestInfo
        , \rawResponses ->
            lookup
                requestInfo
                rawResponses
                |> (\result ->
                        case result of
                            Err error ->
                                Err error

                            Ok ( strippedResponses, value ) ->
                                ( strippedResponses, fn value ) |> Ok
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
getWithSecrets :
    Secrets2.Value String
    -> Decoder a
    -> Request a
getWithSecrets url decoder =
    jsonRequestWithSecrets
        (url
            |> Secrets2.map
                (\okUrl -> { url = okUrl, method = "GET" })
        )
        decoder


{-| TODO
-}
get : String -> Decoder a -> Request a
get url decoder =
    jsonRequest
        { url = url, method = "GET" }
        decoder


{-| TODO
-}
jsonRequest : { url : String, method : String } -> Decoder a -> Request a
jsonRequest url decoder =
    Request
        ( [ Secrets2.succeed url ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get (url |> Pages.Internal.Secrets.hashRequest)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                -- @@@@@ TODO reduce raw responses
                                Ok
                                    ( rawResponseDict
                                    , rawResponse
                                    )

                            Nothing ->
                                url
                                    |> Pages.Internal.Secrets.requestToString
                                    |> Pages.StaticHttpRequest.MissingHttpResponse
                                    |> Err
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
reducedGet : String -> Json.Decode.Exploration.Decoder a -> Request a
reducedGet url decoder =
    reducedJsonRequest { url = url, method = "GET" } decoder


{-| TODO
-}
reducedPost : String -> Json.Decode.Exploration.Decoder a -> Request a
reducedPost url decoder =
    reducedJsonRequest { url = url, method = "POST" } decoder


{-| TODO
-}
reducedJsonRequest : { url : String, method : String } -> Json.Decode.Exploration.Decoder a -> Request a
reducedJsonRequest requestInfo decoder =
    request (Secrets2.succeed requestInfo) decoder


type Expect a
    = ExpectJson (Json.Decode.Exploration.Decoder a)



--    | ExpectString


{-| TODO
-}
request :
    Secrets2.Value
        { method : String

        --            , headers : List Header
        , url : String

        --            , body : Body
        }
    -> Json.Decode.Exploration.Decoder a
    -> Request a
request urlWithSecrets decoder =
    Request
        ( [ urlWithSecrets ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get (Secrets2.maskedLookup urlWithSecrets |> Pages.Internal.Secrets.hashRequest)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                Ok
                                    ( rawResponseDict
                                      --                                        |> Dict.update url (\maybeValue -> Just """{"fake": 123}""")
                                    , rawResponse
                                    )

                            Nothing ->
                                Secrets2.maskedLookup urlWithSecrets
                                    |> Pages.Internal.Secrets.requestToString
                                    |> Pages.StaticHttpRequest.MissingHttpResponse
                                    |> Err
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
                            |> Result.map
                                (\finalRequest ->
                                    ( strippedResponses
                                        |> Dict.insert
                                            (Secrets2.maskedLookup urlWithSecrets |> Pages.Internal.Secrets.hashRequest)
                                            reduced
                                    , finalRequest
                                    )
                                )
                    )
        )


{-| TODO
-}
jsonRequestWithSecrets :
    Secrets2.Value
        { method : String

        --            , headers : List Header
        , url : String

        --            , body : Body
        }
    -> Decoder a
    -> Request a
jsonRequestWithSecrets urlWithSecrets decoder =
    Request
        ( [ urlWithSecrets ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get (Secrets2.maskedLookup urlWithSecrets |> Pages.Internal.Secrets.hashRequest)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                -- @@@@@ TODO reduce raw responses
                                Ok ( rawResponseDict, rawResponse )

                            Nothing ->
                                --                                Err <| "Couldn't find response for url `" ++ Pages.Internal.Secrets.useFakeSecrets urlWithSecrets ++ "`"
                                Secrets2.maskedLookup urlWithSecrets
                                    |> Pages.Internal.Secrets.requestToString
                                    |> Pages.StaticHttpRequest.MissingHttpResponse
                                    |> Err
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
