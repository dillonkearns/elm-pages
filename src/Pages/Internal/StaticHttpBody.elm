module Pages.Internal.StaticHttpBody exposing (Body(..), codec, encode, extractAllBytes)

import Bitwise
import Bytes exposing (Bytes)
import Bytes.Decode
import Codec exposing (Codec)
import Json.Decode
import Json.Encode as Encode
import TsJson.Encode as TsEncode


type Body
    = EmptyBody
    | StringBody String String
    | JsonBody Encode.Value
    | BytesBody String Bytes
    | MultipartBody (List Encode.Value) (List ( String, Bytes ))


encode : TsEncode.Encoder Body
encode =
    TsEncode.union
        (\fEmpty fString fJson fBytes fMultipart body ->
            case body of
                EmptyBody ->
                    fEmpty ()

                StringBody _ content ->
                    fString content

                JsonBody content ->
                    fJson content

                BytesBody _ content ->
                    fBytes content

                MultipartBody parts _ ->
                    fMultipart parts
        )
        |> TsEncode.variant
            (encodeWithType "empty" [])
        |> TsEncode.variant
            (encodeWithType "string"
                [ TsEncode.required "content" identity TsEncode.string
                ]
            )
        |> TsEncode.variant
            (encodeWithType "json"
                [ TsEncode.required "content" identity TsEncode.value
                ]
            )
        |> TsEncode.variant
            (encodeWithType "bytes"
                [ TsEncode.required "content" hashBytes TsEncode.int
                ]
            )
        |> TsEncode.variant
            (encodeWithType "multipart"
                [ TsEncode.required "parts" identity (TsEncode.list TsEncode.value)
                ]
            )
        |> TsEncode.buildUnion


encodeWithType : String -> List (TsEncode.Property a) -> TsEncode.Encoder a
encodeWithType typeName otherFields =
    TsEncode.object <|
        TsEncode.required "type" identity (TsEncode.literal (Encode.string typeName))
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
    Bytes.Decode.loop ( remaining, hash ) bytesLoopStep


bytesLoopStep : ( Int, Int ) -> Bytes.Decode.Decoder (Bytes.Decode.Step ( Int, Int ) Int)
bytesLoopStep ( remaining, hash ) =
    if remaining <= 0 then
        Bytes.Decode.succeed (Bytes.Decode.Done hash)

    else
        Bytes.Decode.map
            (\byte ->
                Bytes.Decode.Loop
                    ( remaining - 1
                    , Bitwise.and 0xFFFFFFFF (Bitwise.xor hash byte * 0x01000193)
                    )
            )
            Bytes.Decode.unsignedInt8


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
