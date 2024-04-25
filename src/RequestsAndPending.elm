module RequestsAndPending exposing (HttpError(..), RawResponse, RequestsAndPending, Response(..), ResponseBody(..), bodyEncoder, get, responseDecoder)

import Base64
import Bytes exposing (Bytes)
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type alias RequestsAndPending =
    Decode.Value


type ResponseBody
    = BytesBody Bytes
    | StringBody String
    | JsonBody Decode.Value
    | WhateverBody


decoder : Decoder Response
decoder =
    Decode.map2 Response
        (Decode.maybe responseDecoder)
        bodyDecoder


bodyDecoder : Decoder ResponseBody
bodyDecoder =
    Decode.field "bodyKind" Decode.string
        |> Decode.andThen
            (\bodyKind ->
                Decode.field "body"
                    (case bodyKind of
                        "bytes" ->
                            Decode.string
                                |> Decode.andThen
                                    (\base64String ->
                                        base64String
                                            |> Base64.toBytes
                                            |> Maybe.map (BytesBody >> Decode.succeed)
                                            |> Maybe.withDefault (Decode.fail "Couldn't parse base64 string into Bytes.")
                                    )

                        "string" ->
                            Decode.string |> Decode.map StringBody

                        "json" ->
                            Decode.value |> Decode.map JsonBody

                        "whatever" ->
                            Decode.succeed WhateverBody

                        _ ->
                            Decode.fail "Unexpected bodyKind."
                    )
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
    Decode.decodeValue
        (Decode.field key
            (Decode.field "response"
                (Decode.oneOf
                    [ Decode.field "elm-pages-internal-error" errorDecoder |> Decode.map Err
                    , decoder |> Decode.map Ok
                    ]
                )
            )
        )
        requestsAndPending
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
