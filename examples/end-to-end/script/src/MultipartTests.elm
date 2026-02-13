module MultipartTests exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.Http
import BackendTaskTest exposing (testScript)
import Base64
import Bytes.Encode
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.StaticHttpBody exposing (Body(..))
import Pages.Script as Script exposing (Script)
import Test


run : Script
run =
    testScript "Multipart"
        [ parseWith "string parts"
            [ BackendTask.Http.stringPart "title" "My Photo"
            , BackendTask.Http.stringPart "description" "A test upload"
            ]
            |> test "string parts are parsed correctly"
                (\{ fields } ->
                    fields
                        |> Expect.equal
                            [ ( "description", "A test upload" )
                            , ( "title", "My Photo" )
                            ]
                )
        , parseWith "bytes part with filename"
            [ BackendTask.Http.stringPart "field1" "hello"
            , BackendTask.Http.bytesPartWithFilename "file" "application/octet-stream" "data.bin"
                (Bytes.Encode.string "hello world"
                    |> Bytes.Encode.encode
                )
            ]
            |> test "mixed string and file parts"
                (\{ fields, files } ->
                    Expect.all
                        [ \_ -> fields |> Expect.equal [ ( "field1", "hello" ) ]
                        , \_ ->
                            files
                                |> Expect.equal
                                    [ ( "file"
                                      , { filename = "data.bin"
                                        , mimeType = "application/octet-stream"
                                        , content = "hello world"
                                        }
                                      )
                                    ]
                        ]
                        ()
                )
        , parseWith "newlines in string value"
            [ BackendTask.Http.stringPart "message" "line1\r\nline2\r\nline3"
            ]
            |> test "CRLF in values"
                (\{ fields } ->
                    fields
                        |> Expect.equal [ ( "message", "line1\r\nline2\r\nline3" ) ]
                )
        , parseWith "unicode in string value"
            [ BackendTask.Http.stringPart "emoji" "\u{1F600}\u{1F389} héllo wörld"
            ]
            |> test "unicode values"
                (\{ fields } ->
                    fields
                        |> Expect.equal [ ( "emoji", "\u{1F600}\u{1F389} héllo wörld" ) ]
                )
        , parseWith "quotes in field name are sanitized"
            [ BackendTask.Http.stringPart "field\"name" "value"
            ]
            |> test "quotes in field name"
                (\{ fields } ->
                    fields
                        |> Expect.equal [ ( "fieldname", "value" ) ]
                )
        , parseWith "CRLF in field name are sanitized"
            [ BackendTask.Http.stringPart "field\r\nname" "value"
            ]
            |> test "CRLF in field name"
                (\{ fields } ->
                    fields
                        |> Expect.equal [ ( "fieldname", "value" ) ]
                )
        , parseWith "dangerous chars in filename are sanitized"
            [ BackendTask.Http.bytesPartWithFilename "file" "text/plain" "evil\"\r\nname.txt"
                (Bytes.Encode.string "content"
                    |> Bytes.Encode.encode
                )
            ]
            |> test "quotes and CRLF in filename"
                (\{ files } ->
                    files
                        |> List.map (\( name, info ) -> ( name, info.filename ))
                        |> Expect.equal [ ( "file", "evilname.txt" ) ]
                )
        , checkRawBytes "CRLF in MIME type are sanitized"
            [ BackendTask.Http.bytesPartWithFilename "file" "text/plain\r\nEvil-Header: injected" "test.txt"
                (Bytes.Encode.string "content"
                    |> Bytes.Encode.encode
                )
            ]
            |> test "CRLF stripped from MIME type in raw bytes"
                (\containsInjection ->
                    -- Without sanitization, the raw bytes would contain
                    -- "\r\nEvil-Header:" as a separate header line.
                    -- With sanitization, the \r\n is stripped so it does not.
                    containsInjection
                        |> Expect.equal False
                )
        , parseWith "binary with CRLF and boundary-like sequences"
            [ BackendTask.Http.bytesPartWithFilename "bin" "application/octet-stream" "tricky.bin"
                (Bytes.Encode.sequence
                    [ Bytes.Encode.string "before\r\n--"
                    , Bytes.Encode.string "fake-boundary\r\n"
                    , Bytes.Encode.string "after"
                    ]
                    |> Bytes.Encode.encode
                )
            ]
            |> test "binary data with CRLF and dashes"
                (\{ files } ->
                    files
                        |> List.map (\( name, info ) -> ( name, info.content ))
                        |> Expect.equal [ ( "bin", "before\r\n--fake-boundary\r\nafter" ) ]
                )
        ]



-- Helpers


{-| Build a multipart body from parts, extract the raw bytes via the internal
Body type, then round-trip through busboy (Node.js) to verify the encoding.
-}
parseWith :
    String
    -> List BackendTask.Http.Part
    -> BackendTask FatalError ParsedMultipart
parseWith label parts =
    let
        multipartResult : BackendTask.Http.Body
        multipartResult =
            BackendTask.Http.multipartBody parts
    in
    case multipartResult of
        BytesBody contentType bytes ->
            BackendTask.Custom.run "parseMultipart"
                (Encode.object
                    [ ( "base64"
                      , Base64.fromBytes bytes
                            |> Maybe.withDefault ""
                            |> Encode.string
                      )
                    , ( "contentType", Encode.string contentType )
                    ]
                )
                parsedMultipartDecoder
                |> try

        _ ->
            BackendTask.fail
                (FatalError.build
                    { title = "Unexpected Body variant"
                    , body = label ++ ": multipartBody did not produce BytesBody"
                    }
                )


{-| Build a multipart body from parts, extract the raw bytes, and check
whether they contain a specific string. Used to verify header injection
is prevented at the byte level (where busboy normalization can't hide it).
-}
checkRawBytes :
    String
    -> List BackendTask.Http.Part
    -> BackendTask FatalError Bool
checkRawBytes label parts =
    let
        multipartResult : BackendTask.Http.Body
        multipartResult =
            BackendTask.Http.multipartBody parts
    in
    case multipartResult of
        BytesBody _ bytes ->
            BackendTask.Custom.run "rawBytesContain"
                (Encode.object
                    [ ( "base64"
                      , Base64.fromBytes bytes
                            |> Maybe.withDefault ""
                            |> Encode.string
                      )
                    , ( "searchFor", Encode.string "\r\nEvil-Header:" )
                    ]
                )
                Decode.bool
                |> try

        _ ->
            BackendTask.fail
                (FatalError.build
                    { title = "Unexpected Body variant"
                    , body = label ++ ": multipartBody did not produce BytesBody"
                    }
                )


type alias ParsedMultipart =
    { fields : List ( String, String )
    , files : List ( String, FileInfo )
    }


type alias FileInfo =
    { filename : String
    , mimeType : String
    , content : String
    }


parsedMultipartDecoder : Decode.Decoder ParsedMultipart
parsedMultipartDecoder =
    Decode.map2 ParsedMultipart
        (Decode.field "fields"
            (Decode.keyValuePairs Decode.string
                |> Decode.map List.sort
            )
        )
        (Decode.field "files"
            (Decode.keyValuePairs fileInfoDecoder
                |> Decode.map (List.sortBy Tuple.first)
            )
        )


fileInfoDecoder : Decode.Decoder FileInfo
fileInfoDecoder =
    Decode.map3 FileInfo
        (Decode.field "filename" Decode.string)
        (Decode.field "mimeType" Decode.string)
        (Decode.field "content" Decode.string)


test : String -> (a -> Expect.Expectation) -> BackendTask FatalError a -> BackendTask FatalError Test.Test
test name toExpectation task =
    BackendTask.succeed ()
        |> Script.doThen task
        |> BackendTask.map
            (\data ->
                Test.test name <|
                    \() -> toExpectation data
            )


try : BackendTask { error | fatal : FatalError } data -> BackendTask FatalError data
try =
    BackendTask.allowFatal
