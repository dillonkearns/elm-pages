module RequestsAndPending exposing (RawResponse, RequestsAndPending, Response(..), ResponseBody(..), batchDecoder, bodyEncoder, decoder, get)

import Base64
import Bytes exposing (Bytes)
import Codec
import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Pages.StaticHttp.Request


type alias RequestsAndPending =
    Decode.Value


type ResponseBody
    = BytesBody Bytes
    | StringBody String
    | JsonBody Decode.Value
    | WhateverBody


batchDecoder : Decoder (List { request : Pages.StaticHttp.Request.Request, response : Response })
batchDecoder =
    Decode.map2 (\request response -> { request = request, response = response })
        (Decode.field "request"
            (Pages.StaticHttp.Request.codec
                |> Codec.decoder
            )
        )
        (Decode.field "response" decoder)
        |> Decode.list


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


get : String -> RequestsAndPending -> Maybe Response
get key requestsAndPending =
    Decode.decodeValue
        (Decode.field key
            (Decode.field "response" decoder)
        )
        requestsAndPending
        |> Result.toMaybe
