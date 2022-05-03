module Fetcher.Route.Signup exposing (load, submit)

import Bytes.Decode
import Effect exposing (Effect)
import FormDecoder
import Http
import Route.Signup


load : Effect (Result Http.Error Route.Signup.Data)
load =
    Http.request
        { expect = Http.expectBytes identity decodeData
        , tracker = Nothing
        , body = Http.emptyBody
        , headers = []
        , url = "/signup"
        , method = "GET"
        , timeout = Nothing
        }
        |> Effect.fromCmd


submit : { headers : List ( String, String ), formFields : List ( String, String ) } -> Effect (Result Http.Error Route.Signup.ActionData)
submit options =
    let
        { contentType, body } =
            FormDecoder.encodeFormData options.formFields
    in
    Http.request
        { expect = Http.expectBytes identity decodeActionData
        , tracker = Nothing
        , body = Http.stringBody contentType body
        , headers = options.headers |> List.map (\( key, value ) -> Http.header key value)
        , url = "/signup/content.dat"
        , method = "POST"
        , timeout = Nothing
        }
        |> Effect.fromCmd


decodeData : Bytes.Decode.Decoder Route.Signup.Data
decodeData =
    Route.Signup.w3_decode_Data


decodeActionData : Bytes.Decode.Decoder Route.Signup.ActionData
decodeActionData =
    Route.Signup.w3_decode_ActionData
