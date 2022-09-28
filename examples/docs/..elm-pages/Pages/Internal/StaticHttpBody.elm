module Pages.Internal.StaticHttpBody exposing (Body(..), codec, encode)

import Codec exposing (Codec)
import Json.Encode as Encode


type Body
    = EmptyBody
    | StringBody String String
    | JsonBody Encode.Value


encode : Body -> Encode.Value
encode body =
    case body of
        EmptyBody ->
            encodeWithType "empty" []

        StringBody _ content ->
            encodeWithType "string"
                [ ( "content", Encode.string content )
                ]

        JsonBody content ->
            encodeWithType "json"
                [ ( "content", content )
                ]


encodeWithType : String -> List ( String, Encode.Value ) -> Encode.Value
encodeWithType typeName otherFields =
    Encode.object <|
        ( "type", Encode.string typeName )
            :: otherFields


codec : Codec Body
codec =
    Codec.custom
        (\vEmpty vString vJson value ->
            case value of
                EmptyBody ->
                    vEmpty

                StringBody a b ->
                    vString a b

                JsonBody body ->
                    vJson body
        )
        |> Codec.variant0 "EmptyBody" EmptyBody
        |> Codec.variant2 "StringBody" StringBody Codec.string Codec.string
        |> Codec.variant1 "JsonBody" JsonBody Codec.value
        |> Codec.buildCustom
