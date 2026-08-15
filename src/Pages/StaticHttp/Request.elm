module Pages.StaticHttp.Request exposing (Request, codec, hash)

import Codec exposing (Codec)
import Dict exposing (Dict)
import FNV1a
import Json.Encode
import Pages.Internal.StaticHttpBody as StaticHttpBody exposing (Body)
import TsJson.Encode as TsEncode


type alias Request =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    , cacheOptions : Maybe Json.Encode.Value
    , env : Dict String String
    , dir : List String
    , quiet : Bool
    }


hash : Request -> String
hash requestDetails =
    requestDetails
        |> TsEncode.encoder
            (TsEncode.object
                [ TsEncode.required "method" .method TsEncode.string
                , TsEncode.required "url" .url TsEncode.string
                , TsEncode.required "headers" .headers (TsEncode.list hashHeader)
                , TsEncode.required "body" .body StaticHttpBody.encode

                -- , TsEncode.required "env" .env (TsEncode.dict identity TsEncode.string)
                -- , TsEncode.required "dir" .dir (TsEncode.list TsEncode.string)
                ]
            )
        |> Json.Encode.encode 0
        |> FNV1a.hash
        |> String.fromInt


hashHeader : TsEncode.Encoder ( String, String )
hashHeader =
    TsEncode.map (\( name, value ) -> name ++ ": " ++ value)
        TsEncode.string


codec : Codec Request
codec =
    Codec.object Request
        |> Codec.field "url" .url Codec.string
        |> Codec.field "method" .method Codec.string
        |> Codec.field "headers" .headers (Codec.list (Codec.tuple Codec.string Codec.string))
        |> Codec.field "body" .body StaticHttpBody.codec
        |> Codec.nullableField "cacheOptions" .cacheOptions Codec.value
        |> Codec.field "env" .env (Codec.dict Codec.string)
        |> Codec.field "dir" .dir (Codec.list Codec.string)
        |> Codec.field "quiet" .quiet Codec.bool
        |> Codec.buildObject
