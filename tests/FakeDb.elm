module FakeDb exposing (Db, get, testConfig, update)

{-| A fake Pages.Db module for testing the DB virtual layer.
Uses simple Bytes encoding (not Wire3) so tests work without lamdera.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Bytes exposing (Bytes)
import Bytes.Decode as BD
import Bytes.Encode as BE
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode


type alias Db =
    { counter : Int
    , name : String
    }


schemaHash : String
schemaHash =
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"


schemaVersion : Int
schemaVersion =
    1


seed : Db
seed =
    { counter = 0, name = "" }


encode : Db -> Bytes
encode db =
    BE.encode
        (BE.sequence
            [ BE.signedInt32 Bytes.BE db.counter
            , encodeString db.name
            ]
        )


encodeString : String -> BE.Encoder
encodeString s =
    let
        strBytes : Bytes
        strBytes =
            BE.encode (BE.string s)
    in
    BE.sequence
        [ BE.unsignedInt32 Bytes.BE (Bytes.width strBytes)
        , BE.bytes strBytes
        ]


decode : Bytes -> Maybe Db
decode bytes =
    BD.decode
        (BD.signedInt32 Bytes.BE
            |> BD.andThen
                (\counter ->
                    BD.unsignedInt32 Bytes.BE
                        |> BD.andThen
                            (\strLen ->
                                BD.string strLen
                                    |> BD.map
                                        (\name ->
                                            { counter = counter, name = name }
                                        )
                            )
                )
        )
        bytes


testConfig :
    { schemaVersion : Int
    , schemaHash : String
    , encode : Db -> Bytes
    , decode : Bytes -> Maybe Db
    , seed : Db
    }
testConfig =
    { schemaVersion = schemaVersion
    , schemaHash = schemaHash
    , encode = encode
    , decode = decode
    , seed = seed
    }


{-| Mimics Pages.Db.get — reads from db-read-meta, decodes the bytes.
-}
get : BackendTask FatalError Db
get =
    BackendTask.Http.request
        { url = "elm-pages-internal://db-read-meta"
        , method = "GET"
        , headers = []
        , body = BackendTask.Http.jsonBody (Encode.object [])
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        (BackendTask.Http.expectBytes dbReadPayloadDecoder)
        |> BackendTask.allowFatal
        |> BackendTask.andThen resolvePayload


type alias DbReadPayload =
    { version : Int
    , hash : String
    , data : Bytes
    }


dbReadPayloadDecoder : BD.Decoder DbReadPayload
dbReadPayloadDecoder =
    BD.unsignedInt32 Bytes.BE
        |> BD.andThen
            (\version ->
                BD.bytes 32
                    |> BD.andThen
                        (\hashBytes ->
                            BD.unsignedInt32 Bytes.BE
                                |> BD.andThen
                                    (\wire3Len ->
                                        BD.bytes wire3Len
                                            |> BD.map
                                                (\wire3 ->
                                                    { version = version
                                                    , hash = bytesToHexString hashBytes
                                                    , data = wire3
                                                    }
                                                )
                                    )
                        )
            )


bytesToHexString : Bytes -> String
bytesToHexString bytes =
    BD.decode (bytesToHexHelp (Bytes.width bytes) []) bytes
        |> Maybe.withDefault ""


bytesToHexHelp : Int -> List String -> BD.Decoder String
bytesToHexHelp remaining acc =
    if remaining <= 0 then
        BD.succeed (String.join "" (List.reverse acc))

    else
        BD.unsignedInt8
            |> BD.andThen
                (\byte ->
                    bytesToHexHelp (remaining - 1) (byteToHex byte :: acc)
                )


byteToHex : Int -> String
byteToHex byte =
    let
        hi : Int
        hi =
            byte // 16

        lo : Int
        lo =
            modBy 16 byte
    in
    String.fromList [ hexDigit hi, hexDigit lo ]


hexDigit : Int -> Char
hexDigit n =
    case n of
        0 ->
            '0'

        1 ->
            '1'

        2 ->
            '2'

        3 ->
            '3'

        4 ->
            '4'

        5 ->
            '5'

        6 ->
            '6'

        7 ->
            '7'

        8 ->
            '8'

        9 ->
            '9'

        10 ->
            'a'

        11 ->
            'b'

        12 ->
            'c'

        13 ->
            'd'

        14 ->
            'e'

        _ ->
            'f'


resolvePayload : DbReadPayload -> BackendTask FatalError Db
resolvePayload payload =
    if payload.version <= 0 || Bytes.width payload.data == 0 then
        BackendTask.succeed seed

    else
        case decode payload.data of
            Just db ->
                BackendTask.succeed db

            Nothing ->
                BackendTask.fail
                    (FatalError.build
                        { title = "DB decode failed"
                        , body = "Could not decode DB data."
                        }
                    )


{-| Mimics Pages.Db.update — lock, read, transform, write, unlock.
-}
update : (Db -> Db) -> BackendTask FatalError ()
update fn =
    acquireLock
        |> BackendTask.andThen
            (\_ ->
                get
                    |> BackendTask.andThen
                        (\db ->
                            write (fn db)
                        )
                    |> BackendTask.andThen
                        (\_ ->
                            releaseLock
                        )
            )


acquireLock : BackendTask FatalError String
acquireLock =
    BackendTask.Http.request
        { url = "elm-pages-internal://db-lock-acquire"
        , method = "GET"
        , headers = []
        , body = BackendTask.Http.jsonBody (Encode.object [])
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        (BackendTask.Http.expectJson Decode.string)
        |> BackendTask.allowFatal


releaseLock : BackendTask FatalError ()
releaseLock =
    BackendTask.Http.request
        { url = "elm-pages-internal://db-lock-release"
        , method = "GET"
        , headers = []
        , body = BackendTask.Http.jsonBody (Encode.object [ ( "token", Encode.string "test-lock-token" ) ])
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        (BackendTask.Http.expectJson (Decode.succeed ()))
        |> BackendTask.allowFatal


write : Db -> BackendTask FatalError ()
write db =
    BackendTask.Http.request
        { url = "elm-pages-internal://db-write"
        , method = "GET"
        , headers = [ ( "x-schema-hash", schemaHash ) ]
        , body = BackendTask.Http.bytesBody "application/octet-stream" (encode db)
        , timeoutInMs = Nothing
        , retries = Nothing
        }
        (BackendTask.Http.expectJson (Decode.succeed ()))
        |> BackendTask.allowFatal
