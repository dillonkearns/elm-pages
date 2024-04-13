module StreamTests exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.Http
import BackendTask.Stream as Stream exposing (Stream, defaultCommandOptions)
import BackendTaskTest exposing (testScript)
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Script as Script exposing (Script)
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
        , Stream.commandWithOptions
            (defaultCommandOptions
                |> Stream.allowNon0Status
            )
            "elm-review"
            [ "--report=json" ]
            |> Stream.readJson (Decode.field "type" Decode.string)
            |> try
            |> test "elm-review"
                (.body >> Expect.equal "review-errors")
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
                                Expect.fail "Expected a failure, but got success!"

                            Err error ->
                                error
                                    |> Expect.equal
                                        (FatalError.build
                                            { title = "Stream Error"
                                            , body = message
                                            }
                                        )
            )


try : BackendTask { error | fatal : FatalError } data -> BackendTask FatalError data
try =
    BackendTask.allowFatal


zipFile : String.String
zipFile =
    "elm-review-report.gz.json"
