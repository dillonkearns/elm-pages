module Pages.Internal.StaticHttpBody exposing (Body(..), codec, encode)

import Base64
import Bytes exposing (Bytes)
import Codec exposing (Codec)
import Json.Decode
import Json.Encode as Encode


type Body
    = EmptyBody
    | StringBody String String
    | JsonBody Encode.Value
    | BytesBody String Bytes


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

        BytesBody _ content ->
            encodeWithType "bytes"
                [ ( "content"
                  , Base64.fromBytes content
                        |> Maybe.withDefault ""
                        |> Encode.string
                  )
                ]


encodeWithType : String -> List ( String, Encode.Value ) -> Encode.Value
encodeWithType typeName otherFields =
    Encode.object <|
        ( "type", Encode.string typeName )
            :: otherFields


codec : Codec Body
codec =
    Codec.custom
        (\vEmpty vString vJson vBytes value ->
            case value of
                EmptyBody ->
                    vEmpty

                StringBody a b ->
                    vString a b

                JsonBody body ->
                    vJson body

                BytesBody contentType body ->
                    vBytes contentType body
        )
        |> Codec.variant0 "EmptyBody" EmptyBody
        |> Codec.variant2 "StringBody" StringBody Codec.string Codec.string
        |> Codec.variant1 "JsonBody" JsonBody Codec.value
        |> Codec.variant2 "BytesBody" BytesBody Codec.string bytesCodec
        |> Codec.buildCustom


bytesCodec : Codec Bytes
bytesCodec =
    Codec.build (Base64.fromBytes >> Maybe.withDefault "" >> Encode.string)
        (Json.Decode.string
            |> Json.Decode.map Base64.toBytes
            |> Json.Decode.andThen
                (\decodedBytes ->
                    case decodedBytes of
                        Just bytes ->
                            Json.Decode.succeed bytes

                        Nothing ->
                            Json.Decode.fail "Couldn't parse bytes."
                )
        )
