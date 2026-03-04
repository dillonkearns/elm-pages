module RequestsAndPending exposing (HttpError(..), RawResponse, RequestsAndPending, Response(..), ResponseBody(..), bodyEncoder, empty, get, responseDecoder)

import Bytes exposing (Bytes)
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type alias RequestsAndPending =
    { json : Decode.Value
    , rawBytes : Dict String Bytes
    }


empty : RequestsAndPending
empty =
    { json = Encode.object []
    , rawBytes = Dict.empty
    }


type ResponseBody
    = BytesBody Bytes
    | StringBody String
    | JsonBody Decode.Value
    | WhateverBody


decoder : Maybe Bytes -> Decoder Response
decoder maybeBytes =
    Decode.map2 Response
        (Decode.maybe responseDecoder)
        (bodyDecoder maybeBytes)


bodyDecoder : Maybe Bytes -> Decoder ResponseBody
bodyDecoder maybeBytes =
    Decode.field "bodyKind" Decode.string
        |> Decode.andThen
            (\bodyKind ->
                case bodyKind of
                    "bytes" ->
                        case maybeBytes of
                            Just b ->
                                Decode.succeed (BytesBody b)

                            Nothing ->
                                Decode.fail "Bytes responses must be sent through the port's bytes field."

                    "string" ->
                        Decode.field "body" (Decode.string |> Decode.map StringBody)

                    "json" ->
                        Decode.field "body" (Decode.value |> Decode.map JsonBody)

                    "whatever" ->
                        Decode.field "body" (Decode.succeed WhateverBody)

                    _ ->
                        Decode.fail "Unexpected bodyKind."
            )


bodyEncoder : ResponseBody -> Encode.Value
bodyEncoder body =
    (case body of
        JsonBody jsonValue ->
            ( "json", jsonValue )

        StringBody string ->
            ( "string", Encode.string string )

        BytesBody _ ->
            ( "Unhandled", Encode.null )

        WhateverBody ->
            ( "whatever", Encode.null )
    )
        |> (\( bodyKind, encodedBody ) ->
                Encode.object
                    [ ( "bodyKind", Encode.string bodyKind )
                    , ( "body", encodedBody )
                    ]
           )


type alias RawResponse =
    { statusCode : Int
    , statusText : String
    , headers : Dict String String
    , url : String
    }


type Response
    = Response (Maybe RawResponse) ResponseBody


responseDecoder : Decoder RawResponse
responseDecoder =
    Decode.map4 RawResponse
        (Decode.field "statusCode" Decode.int)
        (Decode.field "statusText" Decode.string)
        (Decode.field "headers" (Decode.dict Decode.string))
        (Decode.field "url" Decode.string)


get : String -> RequestsAndPending -> Maybe (Result HttpError Response)
get key requestsAndPending =
    let
        maybeBytes : Maybe Bytes
        maybeBytes =
            Dict.get key requestsAndPending.rawBytes
    in
    Decode.decodeValue
        (Decode.field key
            (Decode.field "response"
                (Decode.oneOf
                    [ Decode.field "elm-pages-internal-error" errorDecoder |> Decode.map Err
                    , decoder maybeBytes |> Decode.map Ok
                    ]
                )
            )
        )
        requestsAndPending.json
        |> Result.toMaybe


type HttpError
    = NetworkError
    | Timeout


errorDecoder : Decoder HttpError
errorDecoder =
    Decode.string
        |> Decode.andThen
            (\errorCode ->
                case errorCode of
                    "NetworkError" ->
                        Decode.succeed NetworkError

                    "Timeout" ->
                        Decode.succeed Timeout

                    _ ->
                        Decode.fail "Unhandled error code."
            )
