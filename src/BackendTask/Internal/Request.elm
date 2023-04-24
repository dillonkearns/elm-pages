module BackendTask.Internal.Request exposing (request, request2)

import BackendTask exposing (BackendTask)
import BackendTask.Http exposing (Body, Error(..), Expect)
import Json.Decode exposing (Decoder)
import Json.Encode as Encode


request :
    { name : String
    , body : Body
    , expect : Expect a
    }
    -> BackendTask error a
request ({ name, body, expect } as params) =
    -- elm-review: known-unoptimized-recursion
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
            (\error ->
                let
                    _ =
                        Debug.log "BackendTask.Internal.Request" error
                in
                -- TODO avoid crash here, this should be handled as an internal error
                request params
            )


request2 :
    { name : String
    , body : Body
    , expect : Decoder a
    , errorDecoder : Decoder error
    , onError : Json.Decode.Error -> error
    }
    -> BackendTask error a
request2 ({ name, body, expect, onError, errorDecoder } as params) =
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
            (\error ->
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
