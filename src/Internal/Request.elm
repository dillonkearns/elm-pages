module Internal.Request exposing (Request(..), RequestRecord, fakeRequest, toRequest)

import CookieParser
import Dict exposing (Dict)
import Json.Decode as Decode
import Time


type Request
    = Request RequestRecord


type alias RequestRecord =
    { time : Time.Posix
    , method : String
    , body : Maybe String
    , rawUrl : String
    , rawHeaders : Dict String String
    , cookies : Dict String String
    }


toRequest : Decode.Value -> Request
toRequest value =
    Decode.decodeValue requestDecoder value
        |> Result.map Request
        |> Result.withDefault fakeRequest


fakeRequest : Request
fakeRequest =
    Request
        { time = Time.millisToPosix 0
        , method = "ERROR"
        , body = Just "ERROR"
        , rawUrl = "ERROR"
        , rawHeaders = Dict.empty
        , cookies = Dict.empty
        }


requestDecoder : Decode.Decoder RequestRecord
requestDecoder =
    Decode.map6 RequestRecord
        (Decode.field "requestTime"
            (Decode.int |> Decode.map Time.millisToPosix)
        )
        (Decode.field "method" Decode.string)
        (Decode.maybe (Decode.field "body" Decode.string))
        (Decode.field "rawUrl" Decode.string)
        (Decode.maybe (Decode.field "headers" (Decode.dict Decode.string)) |> Decode.map (Maybe.withDefault Dict.empty))
        (Decode.maybe
            (Decode.field "headers"
                (optionalField "cookie" Decode.string
                    |> Decode.map
                        (Maybe.map CookieParser.parse
                            >> Maybe.withDefault Dict.empty
                        )
                )
            )
            |> Decode.map (Maybe.withDefault Dict.empty)
        )


optionalField : String -> Decode.Decoder a -> Decode.Decoder (Maybe a)
optionalField fieldName decoder_ =
    let
        finishDecoding : Decode.Value -> Decode.Decoder (Maybe a)
        finishDecoding json =
            case Decode.decodeValue (Decode.field fieldName Decode.value) json of
                Ok _ ->
                    -- The field is present, so run the decoder on it.
                    Decode.map Just (Decode.field fieldName decoder_)

                Err _ ->
                    -- The field was missing, which is fine!
                    Decode.succeed Nothing
    in
    Decode.value
        |> Decode.andThen finishDecoding
