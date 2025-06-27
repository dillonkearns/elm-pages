module BackendTask.Internal.Request exposing (request, request2)

import BackendTask exposing (BackendTask)
import BackendTask.Http exposing (Body, Expect)
import Json.Decode exposing (Decoder)
import Json.Encode as Encode
import Pages.StaticHttpRequest


request :
    { name : String
    , body : Body
    , expect : Expect a
    }
    -> BackendTask error a
request { name, body, expect } =
    BackendTask.Http.request
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        expect
        |> BackendTask.onError
            (\err ->
                Pages.StaticHttpRequest.InternalError err.fatal
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
    -- elm-review: known-unoptimized-recursion
    BackendTask.Http.request
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        (BackendTask.Http.expectJson Json.Decode.value)
        |> BackendTask.onError
            (\_ ->
                BackendTask.succeed Encode.null
            )
        |> BackendTask.andThen
            (\decodeValue ->
                case Json.Decode.decodeValue errorDecoder decodeValue of
                    Ok a ->
                        BackendTask.fail a

                    Err _ ->
                        case Json.Decode.decodeValue expect decodeValue of
                            Ok a ->
                                BackendTask.succeed a

                            Err e ->
                                BackendTask.fail (onError e)
            )
