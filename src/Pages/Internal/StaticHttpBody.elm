module Pages.Internal.StaticHttpBody exposing (Body(..), codec, encode, extractAllBytes)

import Bitwise
import Bytes exposing (Bytes)
import Bytes.Decode
import Codec exposing (Codec)
import Json.Decode
import Json.Encode as Encode


type Body
    = EmptyBody
    | StringBody String String
    | JsonBody Encode.Value
    | BytesBody String Bytes
    | MultipartBody (List Encode.Value) (List ( String, Bytes ))


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
                [ ( "content", Encode.int (hashBytes content) )
                ]

        MultipartBody parts _ ->
            encodeWithType "multipart"
                [ ( "parts", Encode.list identity parts )
                ]


encodeWithType : String -> List ( String, Encode.Value ) -> Encode.Value
encodeWithType typeName otherFields =
    Encode.object <|
        ( "type", Encode.string typeName )
            :: otherFields


codec : Codec Body
codec =
    Codec.custom
        (\vEmpty vString vJson vBytes vMultipart value ->
            case value of
                EmptyBody ->
                    vEmpty

                StringBody a b ->
                    vString a b

                JsonBody body ->
                    vJson body

                BytesBody contentType body ->
                    vBytes contentType body

                MultipartBody parts _ ->
                    vMultipart parts
        )
        |> Codec.variant0 "EmptyBody" EmptyBody
        |> Codec.variant2 "StringBody" StringBody Codec.string Codec.string
        |> Codec.variant1 "JsonBody" JsonBody Codec.value
        |> Codec.variant2 "BytesBody" BytesBody Codec.string bytesCodec
        |> Codec.variant1 "MultipartBody" (\parts -> MultipartBody parts []) (Codec.list Codec.value)
        |> Codec.buildCustom


bytesCodec : Codec Bytes
bytesCodec =
    Codec.build
        -- Encode as empty placeholder; real bytes are sent through the port's bytes field
        (\_ -> Encode.string "")
        (Json.Decode.fail "Bytes are sent through the port's bytes field, not JSON.")


hashBytes : Bytes -> Int
hashBytes bytes =
    let
        width : Int
        width =
            Bytes.width bytes
    in
    Bytes.Decode.decode
        (bytesLoop width 0x811C9DC5)
        bytes
        |> Maybe.withDefault 0


bytesLoop : Int -> Int -> Bytes.Decode.Decoder Int
bytesLoop remaining hash =
    if remaining <= 0 then
        Bytes.Decode.succeed hash

    else
        Bytes.Decode.unsignedInt8
            |> Bytes.Decode.andThen
                (\byte ->
                    bytesLoop (remaining - 1)
                        (Bitwise.xor hash byte
                            |> (\h -> h * 0x01000193)
                            |> Bitwise.and 0xFFFFFFFF
                        )
                )


extractAllBytes : String -> Body -> List { key : String, data : Bytes }
extractAllBytes requestHash body =
    case body of
        BytesBody _ bytes ->
            [ { key = requestHash, data = bytes } ]

        MultipartBody _ multipartBytes ->
            multipartBytes
                |> List.map
                    (\( partKey, bytes ) ->
                        { key = requestHash ++ ":multipart:" ++ partKey, data = bytes }
                    )

        _ ->
            []
