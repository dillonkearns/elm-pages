module StreamTests exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.Http exposing (Error(..))
import BackendTask.Stream as Stream exposing (Stream, defaultCommandOptions)
import BackendTaskTest exposing (testScript)
import Dict
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.FatalError exposing (FatalError(..))
import Pages.Script as Script exposing (Script)
import TerminalText exposing (fromAnsiString)
import Test


run : Script
run =
    testScript "Stream"
        [ Stream.fromString "asdf\nqwer\n"
            |> Stream.pipe (Stream.command "wc" [ "-l" ])
            |> Stream.read
            |> try
            |> test "capture stdin"
                (\{ body } ->
                    body
                        |> String.trim
                        |> Expect.equal
                            "2"
                )
        , Stream.fromString "asdf\nqwer\n"
            |> Stream.pipe (Stream.command "wc" [ "-l" ])
            |> Stream.run
            |> test "run stdin"
                (\() ->
                    Expect.pass
                )
        , Stream.command "does-not-exist" []
            |> Stream.run
            |> expectError "command with error"
                "Error: spawn does-not-exist ENOENT"
        , BackendTask.Custom.run "hello"
            Encode.null
            Decode.string
            |> try
            |> test "custom task"
                (Expect.equal "Hello!")
        , Stream.fromString "asdf\nqwer\n"
            |> Stream.pipe (Stream.customDuplex "upperCaseStream" Encode.null)
            |> Stream.read
            |> try
            |> test "custom duplex"
                (.body >> Expect.equal "ASDF\nQWER\n")
        , Stream.customRead "customReadStream" Encode.null
            |> Stream.read
            |> try
            |> test "custom read"
                (.body >> Expect.equal "Hello from customReadStream!")
        , Stream.fromString "qwer\n"
            |> Stream.pipe (Stream.customDuplex "customReadStream" Encode.null)
            |> Stream.read
            |> try
            |> expectError "invalid stream"
                "Expected 'customReadStream' to be a duplex stream!"
        , Stream.fileRead "elm.json"
            |> Stream.pipe Stream.gzip
            |> Stream.pipe (Stream.fileWrite zipFile)
            |> Stream.run
            |> BackendTask.andThen
                (\() ->
                    Stream.fileRead zipFile
                        |> Stream.pipe Stream.unzip
                        |> Stream.readJson (Decode.field "type" Decode.string)
                        |> try
                )
            |> test "zip and unzip" (.body >> Expect.equal "application")
        , Stream.fromString
            """module            Foo
       
a = 1
b =            2
               """
            |> Stream.pipe (Stream.command "elm-format" [ "--stdin" ])
            |> Stream.read
            |> try
            |> test "elm-format --stdin"
                (\{ metadata, body } ->
                    body
                        |> Expect.equal
                            """module Foo exposing (a, b)


a =
    1


b =
    2
"""
                )
        , Stream.fileRead "elm.json"
            |> Stream.pipe
                (Stream.command "jq"
                    [ """."source-directories"[0]"""
                    ]
                )
            |> Stream.readJson Decode.string
            |> try
            |> test "read command output as JSON"
                (.body >> Expect.equal "src")
        , Stream.fromString "invalid elm module"
            |> Stream.pipe
                (Stream.commandWithOptions
                    (defaultCommandOptions
                        |> Stream.allowNon0Status
                        |> Stream.withOutput Stream.MergeStderrAndStdout
                    )
                    "elm-format"
                    [ "--stdin" ]
                )
            |> Stream.read
            |> try
            |> test "stderr"
                (.body >> Expect.equal "Unable to parse file <STDIN>:1:13 To see a detailed explanation, run elm make on the file.\n")
        , Stream.http
            { url = "https://jsonplaceholder.typicode.com/posts/124"
            , timeoutInMs = Nothing
            , body = BackendTask.Http.emptyBody
            , retries = Nothing
            , headers = []
            , method = "GET"
            }
            |> Stream.read
            |> BackendTask.mapError .recoverable
            |> BackendTask.toResult
            |> test "output from HTTP"
                (\result ->
                    case result of
                        Ok _ ->
                            Expect.fail ("Expected a failure, but got success!\n\n" ++ Debug.toString result)

                        Err (Stream.CustomError (BadStatus meta _) _) ->
                            meta.statusCode
                                |> Expect.equal 404

                        _ ->
                            Expect.fail ("Unexpected error\n\n" ++ Debug.toString result)
                )
        , Stream.http
            { url = "https://jsonplaceholder.typicode.com/posts/124"
            , timeoutInMs = Nothing
            , body = BackendTask.Http.emptyBody
            , retries = Nothing
            , headers = []
            , method = "GET"
            }
            |> Stream.read
            |> try
            |> expectError "HTTP FatalError message"
                "BadStatus: 404 Not Found"
        , Stream.fromString "This is input..."
            |> Stream.pipe
                (Stream.customTransformWithMeta
                    "upperCaseStream"
                    Encode.null
                    (Decode.string |> Decode.map Ok)
                )
            |> Stream.read
            |> try
            |> test "duplex meta"
                (Expect.equal
                    { metadata = "Hi! I'm metadata from upperCaseStream!"
                    , body = "THIS IS INPUT..."
                    }
                )
        , Stream.fromString "This is input to writeStream!\n"
            |> Stream.pipe
                (Stream.customWriteWithMeta
                    "customWrite"
                    Encode.null
                    (Decode.string |> Decode.map Ok)
                )
            |> Stream.readMetadata
            |> try
            |> test "writeStream meta"
                (Expect.equal "Hi! I'm metadata from customWriteStream!")
        , Stream.fileRead "does-not-exist"
            |> Stream.run
            |> expectError "file not found error"
                "Error: ENOENT: no such file or directory, open '/Users/dillonkearns/src/github.com/dillonkearns/elm-pages/examples/end-to-end/does-not-exist'"
        , Stream.fromString "This is input..."
            |> Stream.pipe (Stream.fileWrite "/this/is/invalid.txt")
            |> Stream.run
            |> expectError "invalid file write destination"
                "Error: ENOENT: no such file or directory, mkdir '/this'"
        , Stream.gzip
            |> Stream.read
            |> try
            |> BackendTask.do
            |> test "gzip alone is no-op"
                (\() ->
                    Expect.pass
                )
        ]


test : String -> (a -> Expect.Expectation) -> BackendTask FatalError a -> BackendTask FatalError Test.Test
test name toExpectation task =
    --Script.log name
    BackendTask.succeed ()
        |> Script.doThen task
        |> BackendTask.map
            (\data ->
                Test.test name <|
                    \() -> toExpectation data
            )


expectError : String -> String -> BackendTask FatalError a -> BackendTask FatalError Test.Test
expectError name message task =
    task
        |> BackendTask.toResult
        |> BackendTask.map
            (\result ->
                Test.test name <|
                    \() ->
                        case result of
                            Ok data ->
                                --Expect.fail "Expected a failure, but got success!"
                                result
                                    |> Debug.toString
                                    |> Expect.equal "Expected a failure, but got success!"

                            Err error ->
                                let
                                    (FatalError info) =
                                        error
                                in
                                info.body
                                    |> TerminalText.fromAnsiString
                                    |> TerminalText.toPlainString
                                    |> Expect.equal message
            )


try : BackendTask { error | fatal : FatalError } data -> BackendTask FatalError data
try =
    BackendTask.allowFatal


zipFile : String.String
zipFile =
    "elm-review-report.gz.json"
