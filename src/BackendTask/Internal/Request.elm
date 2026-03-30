module BackendTask.Internal.Request exposing (request, request2, requestBytes, requestWithHeaders)

import BackendTask exposing (BackendTask)
import BackendTask.Http exposing (Body)
import Bytes.Decode
import Dict
import FatalError
import Json.Decode exposing (Decoder)
import Json.Encode as Encode
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (RawRequest(..))
import RequestsAndPending


request :
    { name : String
    , body : Body
    , expect : Decoder a
    }
    -> BackendTask error a
request { name, body, expect } =
    requestWithHeaders
        { name = name
        , headers = []
        , body = body
        , expect = expect
        }


requestWithHeaders :
    { name : String
    , headers : List ( String, String )
    , body : Body
    , expect : Decoder a
    }
    -> BackendTask error a
requestWithHeaders { name, headers, body, expect } =
    let
        hashReq : HashRequest.Request
        hashReq =
            buildHashRequest "ExpectJson" name headers body
    in
    Request
        [ hashReq ]
        (\maybeMockResolver rawResponseDict ->
            let
                maybeResponse : Maybe (Result RequestsAndPending.HttpError RequestsAndPending.Response)
                maybeResponse =
                    case maybeMockResolver of
                        Just mockResolver ->
                            mockResolver hashReq |> Maybe.map Ok

                        Nothing ->
                            RequestsAndPending.get (HashRequest.hash hashReq) rawResponseDict
            in
            case maybeResponse of
                Just (Ok (RequestsAndPending.Response _ (RequestsAndPending.JsonBody json))) ->
                    case Json.Decode.decodeValue expect json of
                        Ok val ->
                            ApiRoute (Ok val)

                        Err e ->
                            InternalError (FatalError.fromString (Json.Decode.errorToString e))

                Just (Ok _) ->
                    InternalError (FatalError.fromString "Unexpected response body type for internal request")

                Just (Err _) ->
                    InternalError (FatalError.fromString "Internal request failed")

                Nothing ->
                    InternalError (FatalError.fromString ("INTERNAL ERROR - expected response for internal request: elm-pages-internal://" ++ name))
        )


request2 :
    { name : String
    , body : Body
    , expect : Decoder a
    , errorDecoder : Decoder error
    , onError : Json.Decode.Error -> error
    }
    -> BackendTask error a
request2 { name, body, expect, onError, errorDecoder } =
    let
        hashReq : HashRequest.Request
        hashReq =
            buildHashRequest "ExpectJson" name [] body
    in
    Request
        [ hashReq ]
        (\maybeMockResolver rawResponseDict ->
            let
                maybeResponse : Maybe (Result RequestsAndPending.HttpError RequestsAndPending.Response)
                maybeResponse =
                    case maybeMockResolver of
                        Just mockResolver ->
                            mockResolver hashReq |> Maybe.map Ok

                        Nothing ->
                            RequestsAndPending.get (HashRequest.hash hashReq) rawResponseDict
            in
            case maybeResponse of
                Just (Ok (RequestsAndPending.Response _ (RequestsAndPending.JsonBody json))) ->
                    case Json.Decode.decodeValue errorDecoder json of
                        Ok a ->
                            ApiRoute (Err a)

                        Err _ ->
                            case Json.Decode.decodeValue expect json of
                                Ok a ->
                                    ApiRoute (Ok a)

                                Err e ->
                                    ApiRoute (Err (onError e))

                Just (Ok _) ->
                    InternalError (FatalError.fromString "Unexpected response body type for internal request")

                Just (Err _) ->
                    -- On network error, return null so error decoder can handle it
                    case Json.Decode.decodeValue errorDecoder Encode.null of
                        Ok a ->
                            ApiRoute (Err a)

                        Err _ ->
                            InternalError (FatalError.fromString "Internal request failed")

                Nothing ->
                    InternalError (FatalError.fromString ("INTERNAL ERROR - expected response for internal request: elm-pages-internal://" ++ name))
        )


requestBytes :
    { name : String
    , body : Body
    , expect : Bytes.Decode.Decoder a
    }
    -> BackendTask error a
requestBytes { name, body, expect } =
    requestBytesWithHeaders
        { name = name
        , headers = []
        , body = body
        , expect = expect
        }


requestBytesWithHeaders :
    { name : String
    , headers : List ( String, String )
    , body : Body
    , expect : Bytes.Decode.Decoder a
    }
    -> BackendTask error a
requestBytesWithHeaders { name, headers, body, expect } =
    let
        hashReq : HashRequest.Request
        hashReq =
            buildHashRequest "ExpectBytes" name headers body
    in
    Request
        [ hashReq ]
        (\maybeMockResolver rawResponseDict ->
            let
                maybeResponse : Maybe (Result RequestsAndPending.HttpError RequestsAndPending.Response)
                maybeResponse =
                    case maybeMockResolver of
                        Just mockResolver ->
                            mockResolver hashReq |> Maybe.map Ok

                        Nothing ->
                            RequestsAndPending.get (HashRequest.hash hashReq) rawResponseDict
            in
            case maybeResponse of
                Just (Ok (RequestsAndPending.Response _ (RequestsAndPending.BytesBody rawBytes))) ->
                    case Bytes.Decode.decode expect rawBytes of
                        Just val ->
                            ApiRoute (Ok val)

                        Nothing ->
                            InternalError (FatalError.fromString "Bytes decoding failed for internal request")

                Just (Ok _) ->
                    InternalError (FatalError.fromString "Unexpected response body type for internal bytes request")

                Just (Err _) ->
                    InternalError (FatalError.fromString "Internal request failed")

                Nothing ->
                    InternalError (FatalError.fromString ("INTERNAL ERROR - expected response for internal request: elm-pages-internal://" ++ name))
        )


buildHashRequest : String -> String -> List ( String, String ) -> Body -> HashRequest.Request
buildHashRequest expectKind name extraHeaders body =
    { url = "elm-pages-internal://" ++ name
    , method = "GET"
    , headers = ( "elm-pages-internal", expectKind ) :: extraHeaders
    , body = body
    , dir = []
    , env = Dict.empty
    , quiet = False
    , cacheOptions = Just (Encode.object [])
    }
