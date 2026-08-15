module RequestsAndPending exposing (HttpError(..), RawResponse, RequestsAndPending, Response(..), ResponseBody(..), bodyEncoder, empty, get, responseDecoder)

import Bytes exposing (Bytes)
import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import TsJson.Decode as TsDecode exposing (Decoder)
import TsJson.Encode as TsEncode


type alias RequestsAndPending =
    { json : Decode.Value
    , rawBytes : Dict String Bytes
    }


empty : RequestsAndPending
empty =
    { json = TsEncode.encoder (TsEncode.object []) {}
    , rawBytes = Dict.empty
    }


type ResponseBody
    = BytesBody Bytes
    | StringBody String
    | JsonBody Decode.Value
    | WhateverBody


decoder : Maybe Bytes -> Decoder Response
decoder maybeBytes =
    TsDecode.map2 Response
        (TsDecode.maybe responseDecoder)
        (bodyDecoder maybeBytes)


bodyDecoder : Maybe Bytes -> Decoder ResponseBody
bodyDecoder maybeBytes =
    TsDecode.discriminatedUnion "bodyKind"
        [ ( "bytes"
          , case maybeBytes of
                Just b ->
                    TsDecode.succeed (BytesBody b)

                Nothing ->
                    TsDecode.fail "Bytes responses must be sent through the port's bytes field."
          )
        , ( "string"
          , TsDecode.field "body" (TsDecode.string |> TsDecode.map StringBody)
          )
        , ( "json"
          , TsDecode.field "body" (TsDecode.value |> TsDecode.map JsonBody)
          )
        , ( "whatever"
          , TsDecode.field "body" (TsDecode.succeed WhateverBody)
          )
        ]


bodyEncoder : TsEncode.Encoder ResponseBody
bodyEncoder =
    let
        variant :
            String
            -> TsEncode.Encoder a
            -> TsEncode.UnionBuilder ((a -> TsEncode.UnionEncodeValue) -> match)
            -> TsEncode.UnionBuilder match
        variant bodyKind body =
            TsEncode.variant
                (TsEncode.object
                    [ TsEncode.required "bodyKind"
                        identity
                        (TsEncode.literal (Encode.string bodyKind))
                    , TsEncode.required "body" identity body
                    ]
                )
    in
    TsEncode.union
        (\fJson fString fBytes fWhatever body ->
            case body of
                JsonBody jsonValue ->
                    fJson jsonValue

                StringBody string ->
                    fString string

                BytesBody _ ->
                    fBytes ()

                WhateverBody ->
                    fWhatever ()
        )
        |> variant "json" TsEncode.value
        |> variant "string" TsEncode.string
        |> variant "Unhandled" TsEncode.null
        |> variant "whatever" TsEncode.null
        |> TsEncode.buildUnion


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
    TsDecode.map4 RawResponse
        (TsDecode.field "statusCode" TsDecode.int)
        (TsDecode.field "statusText" TsDecode.string)
        (TsDecode.field "headers" (TsDecode.dict TsDecode.string))
        (TsDecode.field "url" TsDecode.string)


get : String -> RequestsAndPending -> Maybe (Result HttpError Response)
get key requestsAndPending =
    let
        maybeBytes : Maybe Bytes
        maybeBytes =
            Dict.get key requestsAndPending.rawBytes
    in
    Decode.decodeValue
        (TsDecode.decoder
            (TsDecode.at [ key, "response" ]
                (TsDecode.oneOf
                    [ TsDecode.field "elm-pages-internal-error" errorDecoder |> TsDecode.map Err
                    , decoder maybeBytes |> TsDecode.map Ok
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
    TsDecode.stringUnion
        [ ( "NetworkError", NetworkError )
        , ( "Timeout", Timeout )
        ]
