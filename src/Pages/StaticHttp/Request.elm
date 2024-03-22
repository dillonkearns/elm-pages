module Pages.StaticHttp.Request exposing (Request, codec, hash)

import Codec exposing (Codec)
import Dict exposing (Dict)
import FNV1a
import Json.Encode as Encode
import Pages.Internal.StaticHttpBody as StaticHttpBody exposing (Body)


type alias Request =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    , cacheOptions : Maybe Encode.Value
    , env : Dict String String
    , dir : List String
    }


hash : Request -> String
hash requestDetails =
    Encode.object
        [ ( "method", Encode.string requestDetails.method )
        , ( "url", Encode.string requestDetails.url )
        , ( "headers", Encode.list hashHeader requestDetails.headers )
        , ( "body", StaticHttpBody.encode requestDetails.body )
        ]
        |> Encode.encode 0
        |> FNV1a.hash
        |> String.fromInt


hashHeader : ( String, String ) -> Encode.Value
hashHeader ( name, value ) =
    Encode.string <| name ++ ": " ++ value


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
        |> Codec.buildObject
