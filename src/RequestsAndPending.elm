module RequestsAndPending exposing (RequestsAndPending, Response(..), ResponseBody(..), decoder, get, responseKindString)

import Base64
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
