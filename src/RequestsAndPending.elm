module RequestsAndPending exposing (RequestsAndPending, Response(..), ResponseBody(..), decoder, get, responseKindString)

import Bytes exposing (Bytes)
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)


type alias RequestsAndPending =
    Dict String (Maybe Response)


type ResponseBody
    = BytesBody Bytes
    | StringBody String
    | JsonBody Decode.Value
    | WhateverBody


decoder : Maybe Bytes -> Decoder Response
decoder maybeBytes =
    Decode.map2 Response
        (Decode.maybe responseDecoder)
        (decoder_ maybeBytes)


decoder_ : Maybe Bytes -> Decoder ResponseBody
decoder_ maybeBytesBody =
    Decode.field "bodyKind" Decode.string
        |> Decode.andThen
            (\bodyKind ->
                Decode.field "body"
                    (case bodyKind of
                        "bytes" ->
                            maybeBytesBody
                                |> Maybe.map (BytesBody >> Decode.succeed)
                                |> Maybe.withDefault (Decode.fail "Internal error - found bytes body so I expected maybeBytes but was Nothing.")

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


type alias RawResponse =
    { statusCode : Int
    , statusText : String
    , headers : Dict String String
    , url : String
    }


type Response
    = Response (Maybe RawResponse) ResponseBody


responseKindString : ResponseBody -> String
responseKindString body =
    case body of
        BytesBody _ ->
            "BytesBody"

        StringBody _ ->
            "StringBody"

        JsonBody _ ->
            "JsonBody"

        WhateverBody ->
            "WhateverBody"


responseDecoder : Decoder RawResponse
responseDecoder =
    Decode.map4 RawResponse
        (Decode.field "statusCode" Decode.int)
        (Decode.field "statusText" Decode.string)
        (Decode.field "headers" (Decode.dict Decode.string))
        (Decode.field "url" Decode.string)


get : String -> RequestsAndPending -> Maybe Response
get key requestsAndPending =
    requestsAndPending
        |> Dict.get key
        |> Maybe.andThen identity
