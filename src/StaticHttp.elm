module StaticHttp exposing
    ( Request, RequestDetails
    , get, request
    , map, succeed
    , andThen, resolve, combine
    , map2, map3, map4, map5, map6, map7, map8, map9
    )

{-| TODO

@docs Request, RequestDetails
@docs get, request
@docs map, succeed


## Chaining Requests

@docs andThen, resolve, combine

@docs map2, map3, map4, map5, map6, map7, map8, map9

-}

import Dict exposing (Dict)
import Dict.Extra
import Json.Decode.Exploration as Decode exposing (Decoder)
import Pages.StaticHttpRequest exposing (Request(..))
import Secrets


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
resolve : Request (List (Request value)) -> Request (List value)
resolve topRequest =
    topRequest
        |> andThen
            (\continuationRequests -> combine continuationRequests)


{-| TODO
-}
combine : List (Request value) -> Request (List value)
combine requests =
    requests
        |> List.foldl (map2 (::)) (succeed [])


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


addUrls : List (Secrets.Value { url : String, method : String, headers : List ( String, String ) }) -> Pages.StaticHttpRequest.Request value -> Pages.StaticHttpRequest.Request value
addUrls urlsToAdd requestInfo =
    case requestInfo of
        Request ( initialUrls, function ) ->
            Request ( initialUrls ++ urlsToAdd, function )

        Done value ->
            Done value


lookupUrls : Pages.StaticHttpRequest.Request value -> List (Secrets.Value RequestDetails)
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
get :
    Secrets.Value String
    -> Decoder a
    -> Request a
get url decoder =
    request
        (url
            |> Secrets.map
                (\okUrl -> { url = okUrl, method = "GET", headers = [] })
        )
        decoder


{-| TODO
-}
type alias RequestDetails =
    { url : String, method : String, headers : List ( String, String ) }


hashRequest : RequestDetails -> String
hashRequest requestDetails =
    "["
        ++ requestDetails.method
        ++ "]"
        ++ requestDetails.url
        ++ String.join "," (requestDetails.headers |> List.map (\( key, value ) -> key ++ " : " ++ value))


requestToString : RequestDetails -> String
requestToString requestDetails =
    requestDetails.url


{-| TODO
-}
request :
    Secrets.Value RequestDetails
    -> Decoder a
    -> Request a
request urlWithSecrets decoder =
    Request
        ( [ urlWithSecrets ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get (Secrets.maskedLookup urlWithSecrets |> hashRequest)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                Ok
                                    ( rawResponseDict
                                      --                                        |> Dict.update url (\maybeValue -> Just """{"fake": 123}""")
                                    , rawResponse
                                    )

                            Nothing ->
                                Secrets.maskedLookup urlWithSecrets
                                    |> requestToString
                                    |> Pages.StaticHttpRequest.MissingHttpResponse
                                    |> Err
                   )
                |> Result.andThen
                    (\( strippedResponses, rawResponse ) ->
                        let
                            reduced =
                                Decode.stripString decoder rawResponse
                                    |> Result.withDefault "TODO"
                        in
                        rawResponse
                            |> Decode.decodeString decoder
                            --                                                        |> Result.mapError Json.Decode.Exploration.errorsToString
                            |> (\decodeResult ->
                                    case decodeResult of
                                        Decode.BadJson ->
                                            Pages.StaticHttpRequest.DecoderError "Payload sent back invalid JSON" |> Err

                                        Decode.Errors errors ->
                                            errors
                                                |> Decode.errorsToString
                                                |> Pages.StaticHttpRequest.DecoderError
                                                |> Err

                                        Decode.WithWarnings warnings a ->
                                            --                                            Pages.StaticHttpRequest.DecoderError "" |> Err
                                            Ok a

                                        Decode.Success a ->
                                            Ok a
                               )
                            --                            |> Result.mapError Pages.StaticHttpRequest.DecoderError
                            |> Result.map Done
                            |> Result.map
                                (\finalRequest ->
                                    ( strippedResponses
                                        |> Dict.insert
                                            (Secrets.maskedLookup urlWithSecrets |> hashRequest)
                                            reduced
                                    , finalRequest
                                    )
                                )
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
map3 combineFn request1 request2 request3 =
    succeed combineFn
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
map4 combineFn request1 request2 request3 request4 =
    succeed combineFn
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
map5 combineFn request1 request2 request3 request4 request5 =
    succeed combineFn
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
map6 combineFn request1 request2 request3 request4 request5 request6 =
    succeed combineFn
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
map7 combineFn request1 request2 request3 request4 request5 request6 request7 =
    succeed combineFn
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
map8 combineFn request1 request2 request3 request4 request5 request6 request7 request8 =
    succeed combineFn
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
map9 combineFn request1 request2 request3 request4 request5 request6 request7 request8 request9 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7
        |> map2 (|>) request8
        |> map2 (|>) request9
