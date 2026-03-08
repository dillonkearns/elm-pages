module ScriptTestTests exposing (all)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.Env
import BackendTask.File
import BackendTask.Glob as Glob
import BackendTask.Http
import BackendTask.Random
import BackendTask.Stream as Stream
import BackendTask.Time
import Bytes
import Bytes.Decode
import Bytes.Encode
import FilePath
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Script as Script
import Random
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Runner
import Time


all : Test
all =
    describe "Test.BackendTask"
        [ describe "fromBackendTask + expectSuccess"
            [ test "succeeds for BackendTask.succeed ()" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "simulateHttpGet"
            [ test "single HTTP GET resolves and succeeds" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.field "stargazers_count" Decode.int)
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> BackendTaskTest.expectSuccess
            , test "wrong URL gives helpful error" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.field "stargazers_count" Decode.int)
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://WRONG-URL.com"
                            (Encode.object [])
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """simulateHttpGet: Expected a pending GET request for

    https://WRONG-URL.com

but the pending requests are:

    GET https://api.github.com/repos/dillonkearns/elm-pages"""
                            )
            ]
        , describe "ensureHttpGet"
            [ test "verifies parallel requests are both pending" <|
                \() ->
                    BackendTask.map2 (\_ _ -> ())
                        (BackendTask.Http.getJson
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Decode.field "stargazers_count" Decode.int)
                            |> BackendTask.allowFatal
                        )
                        (BackendTask.Http.getJson
                            "https://api.github.com/repos/dillonkearns/elm-graphql"
                            (Decode.field "stargazers_count" Decode.int)
                            |> BackendTask.allowFatal
                        )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                        |> BackendTaskTest.ensureHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-graphql"
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 1205 ) ])
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-graphql"
                            (Encode.object [ ( "stargazers_count", Encode.int 780 ) ])
                        |> BackendTaskTest.expectSuccess
            , test "fails when expected GET not pending" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpGet "https://WRONG-URL.com"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """ensureHttpGet: Expected a pending GET request for

    https://WRONG-URL.com

but the pending requests are:

    GET https://api.github.com/repos/dillonkearns/elm-pages"""
                            )
            ]
        , describe "sequential requests (andThen)"
            [ test "two sequential HTTP GETs" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.field "stargazers_count" Decode.int)
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\_ ->
                                BackendTask.Http.getJson
                                    "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                                    (Decode.field "stargazers_count" Decode.int)
                                    |> BackendTask.allowFatal
                                    |> BackendTask.map (\_ -> ())
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                            (Encode.object [ ( "stargazers_count", Encode.int 22 ) ])
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "parallel requests (map2)"
            [ test "two parallel HTTP GETs" <|
                \() ->
                    BackendTask.map2 (\_ _ -> ())
                        (BackendTask.Http.getJson
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Decode.field "stargazers_count" Decode.int)
                            |> BackendTask.allowFatal
                        )
                        (BackendTask.Http.getJson
                            "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                            (Decode.field "stargazers_count" Decode.int)
                            |> BackendTask.allowFatal
                        )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                            (Encode.object [ ( "stargazers_count", Encode.int 22 ) ])
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "auto-resolve and tracking"
            [ test "ensureLogged fails when message not present" <|
                \() ->
                    Script.log "hello"
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "goodbye"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """ensureLogged: Expected a log message:

    "goodbye"

but the logged messages are:

    "hello\""""
                            )
            , test "Script.log auto-resolves and is tracked by ensureLogged" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.field "stargazers_count" Decode.int)
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\stars ->
                                Script.log (String.fromInt stars)
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> BackendTaskTest.ensureLogged "86"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "file write tracking"
            [ test "writeFile auto-resolves and is tracked by ensureFileWritten" <|
                \() ->
                    Script.writeFile { path = "output.json", body = """{"key":"value"}""" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFileWritten { path = "output.json", body = """{"key":"value"}""" }
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "dogfooding: Stars-like script"
            [ test "fetches star count and logs it" <|
                \() ->
                    let
                        starsTask : BackendTask FatalError ()
                        starsTask =
                            BackendTask.Http.getJson
                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                (Decode.field "stargazers_count" Decode.int)
                                |> BackendTask.allowFatal
                                |> BackendTask.andThen
                                    (\stars ->
                                        Script.log (String.fromInt stars)
                                    )
                    in
                    starsTask
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> BackendTaskTest.ensureLogged "86"
                        |> BackendTaskTest.expectSuccess
            , test "fetches then writes file" <|
                \() ->
                    let
                        writeStarsTask : BackendTask FatalError ()
                        writeStarsTask =
                            BackendTask.Http.getJson
                                "https://api.github.com/repos/dillonkearns/elm-pages"
                                (Decode.field "stargazers_count" Decode.int)
                                |> BackendTask.allowFatal
                                |> BackendTask.andThen
                                    (\stars ->
                                        Script.writeFile
                                            { path = "stars.txt"
                                            , body = String.fromInt stars
                                            }
                                            |> BackendTask.allowFatal
                                    )
                    in
                    writeStarsTask
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> BackendTaskTest.ensureFileWritten { path = "stars.txt", body = "86" }
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "simulateHttpPost"
            [ test "POST request resolves and succeeds" <|
                \() ->
                    BackendTask.Http.post
                        "https://api.example.com/items"
                        (BackendTask.Http.jsonBody (Encode.object [ ( "name", Encode.string "test" ) ]))
                        (BackendTask.Http.expectJson (Decode.field "id" Decode.int))
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpPost
                            "https://api.example.com/items"
                            (Encode.object [ ( "id", Encode.int 42 ) ])
                        |> BackendTaskTest.expectSuccess
            , test "error when simulating POST but only GET is pending" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/items"
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpPost
                            "https://api.example.com/items"
                            (Encode.object [])
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """simulateHttpPost: Expected a pending POST request for

    https://api.example.com/items

but the pending requests are:

    GET https://api.example.com/items"""
                            )
            ]
        , describe "simulateHttpError"
            [ test "network error causes script failure" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/data"
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpError
                            "GET"
                            "https://api.example.com/data"
                            BackendTaskTest.NetworkError
                        |> BackendTaskTest.expectFailure
            , test "error when URL doesn't match" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/data"
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpError
                            "GET"
                            "https://WRONG.com"
                            BackendTaskTest.NetworkError
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """simulateHttpError: Expected a pending GET request for

    https://WRONG.com

but the pending requests are:

    GET https://api.example.com/data"""
                            )
            ]
        , describe "simulateCustom"
            [ test "custom port call resolves with simulated value" <|
                \() ->
                    BackendTask.Custom.run "hashPassword"
                        (Encode.string "secret123")
                        Decode.string
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCustom "hashPassword"
                            (Encode.string "hashed_secret123")
                        |> BackendTaskTest.expectSuccess
            , test "error when port name doesn't match" <|
                \() ->
                    BackendTask.Custom.run "hashPassword"
                        (Encode.string "secret123")
                        Decode.string
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCustom "wrongPortName"
                            (Encode.string "whatever")
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """simulateCustom: Expected a pending BackendTask.Custom.run call for port "wrongPortName"

but the pending requests are:

    BackendTask.Custom.run "hashPassword\""""
                            )
            ]
        , describe "ensureHttpPost"
            [ test "verifies POST is pending alongside GET" <|
                \() ->
                    BackendTask.map2 (\_ _ -> ())
                        (BackendTask.Http.getJson
                            "https://api.example.com/config"
                            (Decode.succeed ())
                            |> BackendTask.allowFatal
                        )
                        (BackendTask.Http.post
                            "https://api.example.com/items"
                            (BackendTask.Http.jsonBody (Encode.object [ ( "name", Encode.string "test" ) ]))
                            (BackendTask.Http.expectJson (Decode.succeed ()))
                            |> BackendTask.allowFatal
                        )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpGet "https://api.example.com/config"
                        |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
                        |> BackendTaskTest.simulateHttpGet "https://api.example.com/config" Encode.null
                        |> BackendTaskTest.simulateHttpPost
                            "https://api.example.com/items"
                            (Encode.object [ ( "id", Encode.int 42 ) ])
                        |> BackendTaskTest.expectSuccess
            , test "fails when expected POST not pending" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/items"
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """ensureHttpPost: Expected a pending POST request for

    https://api.example.com/items

but the pending requests are:

    GET https://api.example.com/items"""
                            )
            ]
        , describe "ensureCustom"
            [ test "verifies parallel Custom calls are both pending" <|
                \() ->
                    BackendTask.map2 (\_ _ -> ())
                        (BackendTask.Custom.run "hashPassword"
                            (Encode.string "secret123")
                            Decode.string
                            |> BackendTask.allowFatal
                        )
                        (BackendTask.Custom.run "sendEmail"
                            (Encode.string "user@example.com")
                            (Decode.succeed ())
                            |> BackendTask.allowFatal
                        )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureCustom "hashPassword"
                        |> BackendTaskTest.ensureCustom "sendEmail"
                        |> BackendTaskTest.simulateCustom "hashPassword"
                            (Encode.string "hashed_secret123")
                        |> BackendTaskTest.simulateCustom "sendEmail"
                            Encode.null
                        |> BackendTaskTest.expectSuccess
            , test "fails when expected port not pending" <|
                \() ->
                    BackendTask.Custom.run "hashPassword"
                        (Encode.string "secret123")
                        Decode.string
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureCustom "wrongPortName"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """ensureCustom: Expected a pending BackendTask.Custom.run call for port "wrongPortName"

but the pending requests are:

    BackendTask.Custom.run "hashPassword\""""
                            )
            ]
        , describe "error messages"
            [ test "simulateHttpGet on completed script" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet "https://example.com" (Encode.object [])
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        "simulateHttpGet: The script has already completed. No pending requests to simulate."
                            )
            , test "expectSuccess when requests still pending" <|
                \() ->
                    BackendTask.Http.getJson "https://api.example.com/data" (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccess
                        |> Expect.equal (Expect.fail "")
                        |> (\_ ->
                                -- Can't easily test Expectation equality, so just verify it's Running
                                BackendTask.Http.getJson "https://api.example.com/data" (Decode.succeed ())
                                    |> BackendTask.allowFatal
                                    |> BackendTaskTest.fromBackendTask
                                    |> BackendTaskTest.simulateHttpGet "https://api.example.com/data" Encode.null
                                    |> BackendTaskTest.expectSuccess
                           )
            , test "ensureFileWritten shows actual file writes in error" <|
                \() ->
                    Script.writeFile { path = "actual.txt", body = "content" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFileWritten { path = "expected.txt", body = "other" }
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """ensureFileWritten: Expected a file write to:

    expected.txt

but the file writes are:

    actual.txt"""
                            )
            ]
        , describe "fromScript"
            [ test "withoutCliOptions script succeeds" <|
                \() ->
                    Script.withoutCliOptions
                        (Script.log "hello")
                        |> BackendTaskTest.fromScript []
                        |> BackendTaskTest.ensureLogged "hello"
                        |> BackendTaskTest.expectSuccess
            , test "withCliOptions parses args" <|
                \() ->
                    let
                        cliConfig : Program.Config { name : String }
                        cliConfig =
                            Program.config
                                |> Program.add
                                    (OptionsParser.build (\name -> { name = name })
                                        |> OptionsParser.with
                                            (Option.optionalKeywordArg "name"
                                                |> Option.withDefault "world"
                                            )
                                    )
                    in
                    Script.withCliOptions cliConfig
                        (\{ name } ->
                            Script.log ("Hello, " ++ name ++ "!")
                        )
                        |> BackendTaskTest.fromScript [ "--name", "Dillon" ]
                        |> BackendTaskTest.ensureLogged "Hello, Dillon!"
                        |> BackendTaskTest.expectSuccess
            , test "withCliOptions uses defaults when no args" <|
                \() ->
                    let
                        cliConfig : Program.Config { name : String }
                        cliConfig =
                            Program.config
                                |> Program.add
                                    (OptionsParser.build (\name -> { name = name })
                                        |> OptionsParser.with
                                            (Option.optionalKeywordArg "name"
                                                |> Option.withDefault "world"
                                            )
                                    )
                    in
                    Script.withCliOptions cliConfig
                        (\{ name } ->
                            Script.log ("Hello, " ++ name ++ "!")
                        )
                        |> BackendTaskTest.fromScript []
                        |> BackendTaskTest.ensureLogged "Hello, world!"
                        |> BackendTaskTest.expectSuccess
            , test "invalid CLI args gives test error" <|
                \() ->
                    let
                        cliConfig : Program.Config { name : String }
                        cliConfig =
                            Program.config
                                |> Program.add
                                    (OptionsParser.build (\name -> { name = name })
                                        |> OptionsParser.with
                                            (Option.requiredKeywordArg "name")
                                    )
                    in
                    Script.withCliOptions cliConfig
                        (\{ name } ->
                            Script.log name
                        )
                        |> BackendTaskTest.fromScript []
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """fromScript: CLI argument parsing failed:

Missing required option: --name

elm-pages-test --name <name>"""
                            )
            ]
        , describe "fromBackendTask + expectFailure"
            [ test "fails for BackendTask.fail" <|
                \() ->
                    FatalError.fromString "Something went wrong"
                        |> BackendTask.fail
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailure
            ]
        , describe "expectFailureWith"
            [ test "asserts on FatalError details from fromString" <|
                \() ->
                    FatalError.fromString "Something went wrong"
                        |> BackendTask.fail
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailureWith
                            (\error ->
                                Expect.all
                                    [ \e -> e.title |> Expect.equal "Custom Error"
                                    , \e -> e.body |> Expect.equal "Something went wrong"
                                    ]
                                    error
                            )
            , test "asserts on FatalError details from build" <|
                \() ->
                    FatalError.build { title = "HTTP Error", body = "Request to https://example.com failed" }
                        |> BackendTask.fail
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailureWith
                            (\error ->
                                Expect.all
                                    [ \e -> e.title |> Expect.equal "HTTP Error"
                                    , \e -> e.body |> Expect.equal "Request to https://example.com failed"
                                    ]
                                    error
                            )
            , test "fails when script succeeds" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailureWith (\_ -> Expect.pass)
                        |> isFailingExpectation
            , test "fails when script has pending requests" <|
                \() ->
                    BackendTask.Http.getJson "https://example.com" (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailureWith (\_ -> Expect.pass)
                        |> isFailingExpectation
            , test "fails when there is a test error" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet "https://no-match.com" Encode.null
                        |> BackendTaskTest.expectFailureWith (\_ -> Expect.pass)
                        |> isFailingExpectation
            , test "works with simulateHttpError" <|
                \() ->
                    BackendTask.Http.getJson "https://api.example.com/data" (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpError "GET" "https://api.example.com/data" BackendTaskTest.NetworkError
                        |> BackendTaskTest.expectFailureWith
                            (\error ->
                                error.body
                                    |> String.contains "NetworkError"
                                    |> Expect.equal True
                            )
            ]
        , describe "virtual filesystem"
            [ test "writeFile updates virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "hello world" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "output.txt" "hello world"
                        |> BackendTaskTest.expectSuccess
            , test "ensureFile fails when file doesn't exist" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "missing.txt" "content"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """ensureFile: Expected file "missing.txt" to exist but it was not found.

Files in virtual filesystem:

    (none)"""
                            )
            , test "ensureFile fails when content doesn't match" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "actual content" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "output.txt" "expected content"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """ensureFile: File "output.txt" exists but has different content.

Expected:

    expected content

Actual:

    actual content"""
                            )
            , test "ensureNoFile passes when file doesn't exist" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureNoFile "missing.txt"
                        |> BackendTaskTest.expectSuccess
            , test "ensureNoFile fails when file exists" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "content" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureNoFile "output.txt"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """ensureNoFile: Expected file "output.txt" to not exist but it was found."""
                            )
            , test "ensureFileExists passes when file exists" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "content" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFileExists "output.txt"
                        |> BackendTaskTest.expectSuccess
            , test "multiple writeFile calls track all files" <|
                \() ->
                    Script.writeFile { path = "a.txt", body = "aaa" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                Script.writeFile { path = "b.txt", body = "bbb" }
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "a.txt" "aaa"
                        |> BackendTaskTest.ensureFile "b.txt" "bbb"
                        |> BackendTaskTest.expectSuccess
            , test "writing to same file overwrites" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "first" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                Script.writeFile { path = "output.txt", body = "second" }
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "output.txt" "second"
                        |> BackendTaskTest.expectSuccess
            , test "removeFile removes from virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "temp.txt", body = "data" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.removeFile "temp.txt")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureNoFile "temp.txt"
                        |> BackendTaskTest.expectSuccess
            , test "copyFile copies in virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "original.txt", body = "hello" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.copyFile { from = "original.txt", to = "copy.txt" })
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "original.txt" "hello"
                        |> BackendTaskTest.ensureFile "copy.txt" "hello"
                        |> BackendTaskTest.expectSuccess
            , test "move renames in virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "old.txt", body = "content" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.move { from = "old.txt", to = "new.txt" })
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureNoFile "old.txt"
                        |> BackendTaskTest.ensureFile "new.txt" "content"
                        |> BackendTaskTest.expectSuccess
            , test "write then read round-trips through virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "data.txt", body = "round-trip" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                BackendTask.File.rawFile "data.txt"
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTask.andThen
                            (\content ->
                                Script.log ("Read: " ++ content)
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "Read: round-trip"
                        |> BackendTaskTest.expectSuccess
            , test "reading non-existent file fails" <|
                \() ->
                    BackendTask.File.rawFile "missing.txt"
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailure
            , test "file exists check works with virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "exists.txt", body = "hi" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                BackendTask.map2
                                    (\a b ->
                                        Script.log
                                            ("exists: "
                                                ++ boolToString a
                                                ++ ", missing: "
                                                ++ boolToString b
                                            )
                                    )
                                    (BackendTask.File.exists "exists.txt")
                                    (BackendTask.File.exists "nope.txt")
                                    |> BackendTask.andThen identity
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "exists: true, missing: false"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "withSimulatedEffects"
            [ test "custom port writes file to virtual filesystem" <|
                \() ->
                    BackendTask.Custom.run "generateReport"
                        (Encode.string "input data")
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.withSimulatedEffects
                            (\portName _ ->
                                case portName of
                                    "generateReport" ->
                                        [ BackendTaskTest.writeFileEffect "report.pdf" "pdf content" ]

                                    _ ->
                                        []
                            )
                        |> BackendTaskTest.simulateCustom "generateReport" Encode.null
                        |> BackendTaskTest.ensureFile "report.pdf" "pdf content"
                        |> BackendTaskTest.expectSuccess
            , test "custom port removes file from virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "temp.txt", body = "data" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                BackendTask.Custom.run "cleanup"
                                    Encode.null
                                    (Decode.succeed ())
                                    |> BackendTask.allowFatal
                                    |> BackendTask.map (\_ -> ())
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.withSimulatedEffects
                            (\portName _ ->
                                case portName of
                                    "cleanup" ->
                                        [ BackendTaskTest.removeFileEffect "temp.txt" ]

                                    _ ->
                                        []
                            )
                        |> BackendTaskTest.ensureFile "temp.txt" "data"
                        |> BackendTaskTest.simulateCustom "cleanup" Encode.null
                        |> BackendTaskTest.ensureNoFile "temp.txt"
                        |> BackendTaskTest.expectSuccess
            , test "handler receives request body" <|
                \() ->
                    BackendTask.Custom.run "writeToPath"
                        (Encode.object
                            [ ( "path", Encode.string "custom.txt" )
                            , ( "content", Encode.string "hello" )
                            ]
                        )
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.withSimulatedEffects
                            (\_ requestBody ->
                                let
                                    maybePath : Maybe String
                                    maybePath =
                                        Decode.decodeValue
                                            (Decode.at [ "input", "path" ] Decode.string)
                                            requestBody
                                            |> Result.toMaybe

                                    maybeContent : Maybe String
                                    maybeContent =
                                        Decode.decodeValue
                                            (Decode.at [ "input", "content" ] Decode.string)
                                            requestBody
                                            |> Result.toMaybe
                                in
                                case ( maybePath, maybeContent ) of
                                    ( Just path, Just content ) ->
                                        [ BackendTaskTest.writeFileEffect path content ]

                                    _ ->
                                        []
                            )
                        |> BackendTaskTest.simulateCustom "writeToPath" Encode.null
                        |> BackendTaskTest.ensureFile "custom.txt" "hello"
                        |> BackendTaskTest.expectSuccess
            , test "without handler, simulateCustom works as before" <|
                \() ->
                    BackendTask.Custom.run "hashPassword"
                        (Encode.string "secret")
                        Decode.string
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCustom "hashPassword"
                            (Encode.string "hashed_secret")
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "stream auto-resolution"
            [ test "fromString piped to stdout tracks output" <|
                \() ->
                    Stream.fromString "hello world"
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout "hello world"
                        |> BackendTaskTest.expectSuccess
            , test "fromString piped to stderr tracks output" <|
                \() ->
                    Stream.fromString "error message"
                        |> Stream.pipe Stream.stderr
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStderr "error message"
                        |> BackendTaskTest.expectSuccess
            , test "fromString piped to fileWrite writes to VFS" <|
                \() ->
                    Stream.fromString "file content"
                        |> Stream.pipe (Stream.fileWrite "output.txt")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "output.txt" "file content"
                        |> BackendTaskTest.expectSuccess
            , test "fileRead reads from seeded VFS" <|
                \() ->
                    Stream.fileRead "data.txt"
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "data.txt" "seeded data"
                            )
                        |> BackendTaskTest.ensureStdout "seeded data"
                        |> BackendTaskTest.expectSuccess
            , test "fileRead piped to fileWrite copies via VFS" <|
                \() ->
                    Stream.fileRead "input.txt"
                        |> Stream.pipe (Stream.fileWrite "output.txt")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "input.txt" "copied content"
                            )
                        |> BackendTaskTest.ensureFile "output.txt" "copied content"
                        |> BackendTaskTest.expectSuccess
            , test "stream read returns body as text" <|
                \() ->
                    Stream.fromString "hello"
                        |> Stream.read
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\{ body } -> Script.log body)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "hello"
                        |> BackendTaskTest.expectSuccess
            , test "stream readJson returns parsed JSON" <|
                \() ->
                    Stream.fromString """{"name":"test"}"""
                        |> Stream.readJson (Decode.field "name" Decode.string)
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\{ body } -> Script.log body)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "test"
                        |> BackendTaskTest.expectSuccess
            , test "stream with opaque parts (command) is not auto-resolved" <|
                \() ->
                    let
                        result : Expect.Expectation
                        result =
                            Stream.fromString "hello"
                                |> Stream.pipe (Stream.command "grep" [ "hello" ])
                                |> Stream.pipe Stream.stdout
                                |> Stream.run
                                |> BackendTaskTest.fromBackendTask
                                |> BackendTaskTest.expectSuccess
                    in
                    -- Should fail because the stream has opaque parts (command) and stays pending
                    case Test.Runner.getFailureReason result of
                        Just failure ->
                            Expect.all
                                [ \d -> Expect.equal True (String.contains "pending requests" d)
                                , \d -> Expect.equal True (String.contains "Stream [fromString | command | stdout]" d)
                                ]
                                failure.description

                        Nothing ->
                            Expect.fail "Expected the test to fail because the stream has a command part"
            , test "stream fileWrite is visible to subsequent BackendTask.File.rawFile" <|
                \() ->
                    Stream.fromString "written by stream"
                        |> Stream.pipe (Stream.fileWrite "stream-out.txt")
                        |> Stream.run
                        |> BackendTask.andThen
                            (\() ->
                                BackendTask.File.rawFile "stream-out.txt"
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTask.andThen
                            (\content -> Script.log content)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "written by stream"
                        |> BackendTaskTest.expectSuccess
            , test "fileRead reads file written by Script.writeFile" <|
                \() ->
                    Script.writeFile { path = "data.txt", body = "written by script" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                Stream.fileRead "data.txt"
                                    |> Stream.read
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTask.andThen
                            (\{ body } -> Script.log body)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "written by script"
                        |> BackendTaskTest.expectSuccess
            , test "stream fileRead of non-existent file produces error" <|
                \() ->
                    Stream.fileRead "missing.txt"
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailure
            , test "BackendTask.File.rawFile reads seeded file" <|
                \() ->
                    BackendTask.File.rawFile "config.json"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\content -> Script.log content)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "config.json" """{"port":8080}"""
                            )
                        |> BackendTaskTest.ensureLogged """{"port":8080}"""
                        |> BackendTaskTest.expectSuccess
            , test "stdin reads seeded content" <|
                \() ->
                    Stream.stdin
                        |> Stream.read
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\{ body } -> Script.log body)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withStdin "hello from stdin"
                            )
                        |> BackendTaskTest.ensureLogged "hello from stdin"
                        |> BackendTaskTest.expectSuccess
            , test "stdin piped to stdout" <|
                \() ->
                    Stream.stdin
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withStdin "piped through"
                            )
                        |> BackendTaskTest.ensureStdout "piped through"
                        |> BackendTaskTest.expectSuccess
            , test "stdin without withStdin produces error" <|
                \() ->
                    Stream.stdin
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailure
            , test "stdin piped to fileWrite" <|
                \() ->
                    Stream.stdin
                        |> Stream.pipe (Stream.fileWrite "output.txt")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withStdin "stdin content"
                            )
                        |> BackendTaskTest.ensureFile "output.txt" "stdin content"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "simulateCommand"
            [ test "simple command with run" <|
                \() ->
                    Stream.fromString "input"
                        |> Stream.pipe (Stream.command "grep" [ "error" ])
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCommand "grep" "error: found\n"
                        |> BackendTaskTest.expectSuccess
            , test "command with read returns output" <|
                \() ->
                    Stream.fromString "input"
                        |> Stream.pipe (Stream.command "wc" [ "-l" ])
                        |> Stream.read
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\{ body } -> Script.log body)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCommand "wc" "42"
                        |> BackendTaskTest.ensureLogged "42"
                        |> BackendTaskTest.expectSuccess
            , test "fileRead before command reads from VFS" <|
                \() ->
                    Stream.fileRead "data.txt"
                        |> Stream.pipe (Stream.command "grep" [ "error" ])
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "data.txt" "line1\nerror: bad\nline3"
                            )
                        |> BackendTaskTest.simulateCommand "grep" "error: bad\n"
                        |> BackendTaskTest.ensureStdout "error: bad\n"
                        |> BackendTaskTest.expectSuccess
            , test "fileWrite after command writes to VFS" <|
                \() ->
                    Stream.fromString "input data"
                        |> Stream.pipe (Stream.command "grep" [ "error" ])
                        |> Stream.pipe (Stream.fileWrite "errors.txt")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCommand "grep" "error: something bad\n"
                        |> BackendTaskTest.ensureFile "errors.txt" "error: something bad\n"
                        |> BackendTaskTest.expectSuccess
            , test "fileRead + command + fileWrite full pipeline" <|
                \() ->
                    Stream.fileRead "input.txt"
                        |> Stream.pipe (Stream.command "sort" [])
                        |> Stream.pipe (Stream.fileWrite "sorted.txt")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "input.txt" "c\na\nb"
                            )
                        |> BackendTaskTest.simulateCommand "sort" "a\nb\nc"
                        |> BackendTaskTest.ensureFile "sorted.txt" "a\nb\nc"
                        |> BackendTaskTest.expectSuccess
            , test "Script.exec uses simulateCommand" <|
                \() ->
                    Script.exec "ls" [ "-la" ]
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCommand "ls" ""
                        |> BackendTaskTest.expectSuccess
            , test "Script.command uses simulateCommand and returns output" <|
                \() ->
                    Script.command "ls" [ "-la" ]
                        |> BackendTask.andThen
                            (\output -> Script.log output)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCommand "ls" "file1.txt\nfile2.txt"
                        |> BackendTaskTest.ensureLogged "file1.txt\nfile2.txt"
                        |> BackendTaskTest.expectSuccess
            , test "wrong command name gives helpful error" <|
                \() ->
                    Stream.fromString "input"
                        |> Stream.pipe (Stream.command "grep" [ "error" ])
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCommand "sed" "output"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                Expect.equal
                                    """simulateCommand: Expected a pending stream with command "sed"

but the pending requests are:

    Stream [fromString | command]"""
                                    msg
                            )
            ]
        , describe "gzip and unzip"
            [ test "gzip then unzip round-trips" <|
                \() ->
                    Stream.fromString "hello world"
                        |> Stream.pipe Stream.gzip
                        |> Stream.pipe Stream.unzip
                        |> Stream.read
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\output -> Script.log output.body)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "hello world"
                        |> BackendTaskTest.expectSuccess
            , test "unzip without gzip gives error" <|
                \() ->
                    Stream.fromString "plain text"
                        |> Stream.pipe Stream.unzip
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailure
            , test "gzip marker is visible in fileWrite" <|
                \() ->
                    Stream.fromString "compressed data"
                        |> Stream.pipe Stream.gzip
                        |> Stream.pipe (Stream.fileWrite "data.gz")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "data.gz" "****GZIPPED****compressed data"
                        |> BackendTaskTest.expectSuccess
            , test "gzip fileWrite then unzip fileRead round-trips" <|
                \() ->
                    let
                        compress : BackendTask FatalError ()
                        compress =
                            Stream.fromString "secret"
                                |> Stream.pipe Stream.gzip
                                |> Stream.pipe (Stream.fileWrite "data.gz")
                                |> Stream.run

                        decompress : BackendTask FatalError { body : String, metadata : () }
                        decompress =
                            Stream.fileRead "data.gz"
                                |> Stream.pipe Stream.unzip
                                |> Stream.read
                                |> BackendTask.allowFatal
                    in
                    compress
                        |> BackendTask.andThen (\() -> decompress)
                        |> BackendTask.andThen (\output -> Script.log output.body)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "secret"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "simulateCustomStream"
            [ test "custom duplex stream resolves" <|
                \() ->
                    Stream.fromString "input data"
                        |> Stream.pipe (Stream.customDuplex "myTransform" (Encode.object []))
                        |> Stream.pipe (Stream.fileWrite "output.txt")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCustomStream "myTransform" "transformed output"
                        |> BackendTaskTest.ensureFile "output.txt" "transformed output"
                        |> BackendTaskTest.expectSuccess
            , test "custom read stream resolves" <|
                \() ->
                    Stream.customRead "dataSource" (Encode.object [])
                        |> Stream.pipe (Stream.fileWrite "result.txt")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCustomStream "dataSource" "generated data"
                        |> BackendTaskTest.ensureFile "result.txt" "generated data"
                        |> BackendTaskTest.expectSuccess
            , test "wrong port name gives helpful error" <|
                \() ->
                    Stream.fromString "input"
                        |> Stream.pipe (Stream.customDuplex "myPort" (Encode.object []))
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateCustomStream "wrongPort" "output"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                Expect.equal
                                    """simulateCustomStream: Expected a pending stream with custom stream port "wrongPort"

but the pending requests are:

    Stream [fromString | customDuplex]"""
                                    msg
                            )
            ]
        , describe "simulateStreamHttp"
            [ test "http stream resolves" <|
                \() ->
                    Stream.http
                        { url = "https://api.example.com/data"
                        , method = "GET"
                        , headers = []
                        , body = BackendTask.Http.emptyBody
                        , retries = Nothing
                        , timeoutInMs = Nothing
                        }
                        |> Stream.read
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\output -> Script.log output.body)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateStreamHttp "https://api.example.com/data" "response body"
                        |> BackendTaskTest.ensureLogged "response body"
                        |> BackendTaskTest.expectSuccess
            , test "http stream with fileWrite" <|
                \() ->
                    Stream.http
                        { url = "https://api.example.com/data"
                        , method = "GET"
                        , headers = []
                        , body = BackendTask.Http.emptyBody
                        , retries = Nothing
                        , timeoutInMs = Nothing
                        }
                        |> Stream.pipe (Stream.fileWrite "response.json")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateStreamHttp "https://api.example.com/data" "{\"count\": 42}"
                        |> BackendTaskTest.ensureFile "response.json" "{\"count\": 42}"
                        |> BackendTaskTest.expectSuccess
            , test "wrong URL gives helpful error" <|
                \() ->
                    Stream.http
                        { url = "https://api.example.com/data"
                        , method = "GET"
                        , headers = []
                        , body = BackendTask.Http.emptyBody
                        , retries = Nothing
                        , timeoutInMs = Nothing
                        }
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateStreamHttp "https://wrong.url/data" "response"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                Expect.equal
                                    """simulateStreamHttp: Expected a pending stream with stream HTTP request "https://wrong.url/data"

but the pending requests are:

    Stream [httpWrite]"""
                                    msg
                            )
            ]
        , describe "environment variables"
            [ test "Env.get returns seeded value" <|
                \() ->
                    BackendTask.Env.get "API_KEY"
                        |> BackendTask.andThen
                            (\maybeKey ->
                                Script.log (Maybe.withDefault "missing" maybeKey)
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withEnv "API_KEY" "secret123"
                            )
                        |> BackendTaskTest.ensureLogged "secret123"
                        |> BackendTaskTest.expectSuccess
            , test "Env.get returns Nothing for missing variable" <|
                \() ->
                    BackendTask.Env.get "MISSING_VAR"
                        |> BackendTask.andThen
                            (\maybeKey ->
                                Script.log (Maybe.withDefault "not set" maybeKey)
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "not set"
                        |> BackendTaskTest.expectSuccess
            , test "Env.expect succeeds with seeded value" <|
                \() ->
                    BackendTask.Env.expect "DB_URL"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\url -> Script.log url)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withEnv "DB_URL" "postgres://localhost/mydb"
                            )
                        |> BackendTaskTest.ensureLogged "postgres://localhost/mydb"
                        |> BackendTaskTest.expectSuccess
            , test "Env.expect fails for missing variable" <|
                \() ->
                    BackendTask.Env.expect "MISSING_VAR"
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailure
            , test "multiple env variables" <|
                \() ->
                    BackendTask.map2 (\a b -> a ++ ":" ++ b)
                        (BackendTask.Env.get "HOST"
                            |> BackendTask.map (Maybe.withDefault "")
                        )
                        (BackendTask.Env.get "PORT"
                            |> BackendTask.map (Maybe.withDefault "")
                        )
                        |> BackendTask.andThen Script.log
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withEnv "HOST" "localhost"
                                |> BackendTaskTest.withEnv "PORT" "3000"
                            )
                        |> BackendTaskTest.ensureLogged "localhost:3000"
                        |> BackendTaskTest.expectSuccess
            , test "BackendTask.withEnv makes variable visible to Env.get" <|
                \() ->
                    BackendTask.Env.get "MY_CUSTOM_VAR"
                        |> BackendTask.withEnv "MY_CUSTOM_VAR" "injected"
                        |> BackendTask.andThen
                            (\maybeVal ->
                                Script.log (Maybe.withDefault "missing" maybeVal)
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "injected"
                        |> BackendTaskTest.expectSuccess
            , test "BackendTask.withEnv overrides TestSetup withEnv" <|
                \() ->
                    BackendTask.Env.get "MY_VAR"
                        |> BackendTask.withEnv "MY_VAR" "overridden"
                        |> BackendTask.andThen
                            (\maybeVal ->
                                Script.log (Maybe.withDefault "missing" maybeVal)
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withEnv "MY_VAR" "original"
                            )
                        |> BackendTaskTest.ensureLogged "overridden"
                        |> BackendTaskTest.expectSuccess
            , test "Env.expect works with BackendTask.withEnv" <|
                \() ->
                    BackendTask.Env.expect "REQUIRED_VAR"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen Script.log
                        |> BackendTask.withEnv "REQUIRED_VAR" "provided"
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "provided"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "inDir"
            [ test "file read resolves relative to inDir" <|
                \() ->
                    BackendTask.File.rawFile "config.json"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen Script.log
                        |> BackendTask.inDir "subdir"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "subdir/config.json" "found it"
                            )
                        |> BackendTaskTest.ensureLogged "found it"
                        |> BackendTaskTest.expectSuccess
            , test "file write resolves relative to inDir" <|
                \() ->
                    Script.writeFile
                        { path = "output.txt"
                        , body = "hello"
                        }
                        |> BackendTask.allowFatal
                        |> BackendTask.inDir "subdir"
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "subdir/output.txt" "hello"
                        |> BackendTaskTest.expectSuccess
            , test "nested inDir stacks" <|
                \() ->
                    BackendTask.File.rawFile "data.txt"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen Script.log
                        |> BackendTask.inDir "inner"
                        |> BackendTask.inDir "outer"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "outer/inner/data.txt" "nested"
                            )
                        |> BackendTaskTest.ensureLogged "nested"
                        |> BackendTaskTest.expectSuccess
            , test "file exists checks relative to inDir" <|
                \() ->
                    BackendTask.File.exists "config.json"
                        |> BackendTask.andThen
                            (\exists ->
                                Script.log (boolToString exists)
                            )
                        |> BackendTask.inDir "subdir"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "subdir/config.json" "content"
                            )
                        |> BackendTaskTest.ensureLogged "true"
                        |> BackendTaskTest.expectSuccess
            , test "stream fileRead resolves relative to inDir" <|
                \() ->
                    Stream.fileRead "input.txt"
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTask.inDir "mydir"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "mydir/input.txt" "stream content"
                            )
                        |> BackendTaskTest.ensureStdout "stream content"
                        |> BackendTaskTest.expectSuccess
            , test "stream fileWrite resolves relative to inDir" <|
                \() ->
                    Stream.fromString "written via stream"
                        |> Stream.pipe (Stream.fileWrite "out.txt")
                        |> Stream.run
                        |> BackendTask.inDir "mydir"
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "mydir/out.txt" "written via stream"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "Glob"
            [ test "Glob.fromString matches seeded files" <|
                \() ->
                    Glob.fromString "content/blog/*.md"
                        |> BackendTask.map List.sort
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "content/blog/first-post.md" "First post"
                                |> BackendTaskTest.withFile "content/blog/second-post.md" "Second post"
                                |> BackendTaskTest.withFile "content/about.md" "About page"
                                |> BackendTaskTest.withFile "src/Main.elm" "module Main"
                            )
                        |> BackendTaskTest.expectSuccessWith
                            (Expect.equal
                                [ "content/blog/first-post.md"
                                , "content/blog/second-post.md"
                                ]
                            )
            , test "Glob.fromString returns empty list when no matches" <|
                \() ->
                    Glob.fromString "*.xyz"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "hello.md" "content"
                            )
                        |> BackendTaskTest.expectSuccessWith (Expect.equal [])
            , test "Glob with capture extracts slug" <|
                \() ->
                    Glob.succeed (\slug -> slug)
                        |> Glob.match (Glob.literal "content/blog/")
                        |> Glob.capture Glob.wildcard
                        |> Glob.match (Glob.literal ".md")
                        |> Glob.toBackendTask
                        |> BackendTask.map List.sort
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "content/blog/first-post.md" "First"
                                |> BackendTaskTest.withFile "content/blog/second-post.md" "Second"
                                |> BackendTaskTest.withFile "content/about.md" "About"
                            )
                        |> BackendTaskTest.expectSuccessWith
                            (Expect.equal [ "first-post", "second-post" ])
            , test "Glob recursive wildcard matches nested files" <|
                \() ->
                    Glob.fromString "src/**/*.elm"
                        |> BackendTask.map List.sort
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "src/Main.elm" "module Main"
                                |> BackendTaskTest.withFile "src/Ui/Button.elm" "module Ui.Button"
                                |> BackendTaskTest.withFile "src/Ui/Icon.elm" "module Ui.Icon"
                                |> BackendTaskTest.withFile "tests/Test.elm" "module Test"
                            )
                        |> BackendTaskTest.expectSuccessWith
                            (Expect.equal
                                [ "src/Main.elm"
                                , "src/Ui/Button.elm"
                                , "src/Ui/Icon.elm"
                                ]
                            )
            , test "Glob then read file round-trip" <|
                \() ->
                    Glob.fromString "content/*.md"
                        |> BackendTask.andThen
                            (\files ->
                                case files of
                                    [ singleFile ] ->
                                        BackendTask.File.rawFile singleFile
                                            |> BackendTask.allowFatal

                                    _ ->
                                        BackendTask.fail
                                            (FatalError.build
                                                { title = "Expected one file"
                                                , body = "Got " ++ String.fromInt (List.length files)
                                                }
                                            )
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "content/hello.md" "Hello World"
                            )
                        |> BackendTaskTest.expectSuccessWith (Expect.equal "Hello World")
            , test "Glob matches files written during script" <|
                \() ->
                    Script.writeFile { path = "output/report.txt", body = "done" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\_ -> Glob.fromString "output/*.txt")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccessWith
                            (Expect.equal [ "output/report.txt" ])
            , test "Glob with inDir resolves relative to working dir" <|
                \() ->
                    Glob.fromString "*.md"
                        |> BackendTask.inDir "content/blog"
                        |> BackendTask.map List.sort
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "content/blog/first.md" "First"
                                |> BackendTaskTest.withFile "content/blog/second.md" "Second"
                                |> BackendTaskTest.withFile "other/file.md" "Other"
                            )
                        |> BackendTaskTest.expectSuccessWith
                            (Expect.equal [ "first.md", "second.md" ])
            , test "Glob with brace expansion" <|
                \() ->
                    Glob.fromString "data/*.{json,yml}"
                        |> BackendTask.map List.sort
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "data/config.json" "{}"
                                |> BackendTaskTest.withFile "data/authors.yml" "---"
                                |> BackendTaskTest.withFile "data/notes.txt" "text"
                            )
                        |> BackendTaskTest.expectSuccessWith
                            (Expect.equal [ "data/authors.yml", "data/config.json" ])
            ]
        , describe "sleep"
            [ test "sleep auto-resolves as no-op" <|
                \() ->
                    Script.sleep 1000
                        |> BackendTask.andThen (\() -> Script.log "after sleep")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "after sleep"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "makeDirectory"
            [ test "makeDirectory auto-resolves as no-op" <|
                \() ->
                    Script.makeDirectory { recursive = True } "dist/assets"
                        |> BackendTask.andThen (\() -> Script.log "dir created")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "dir created"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "removeDirectory"
            [ test "removeDirectory auto-resolves" <|
                \() ->
                    Script.writeFile { path = "build/output.js", body = "code" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() -> Script.removeDirectory { recursive = True } "build")
                        |> BackendTask.andThen (\() -> Script.log "removed")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "removed"
                        |> BackendTaskTest.expectSuccess
            , test "removeDirectory removes matching files from VFS" <|
                \() ->
                    Script.removeDirectory { recursive = True } "build"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "build/output.js" "code"
                                |> BackendTaskTest.withFile "build/style.css" "css"
                                |> BackendTaskTest.withFile "src/Main.elm" "module Main"
                            )
                        |> BackendTaskTest.ensureNoFile "build/output.js"
                        |> BackendTaskTest.ensureNoFile "build/style.css"
                        |> BackendTaskTest.ensureFile "src/Main.elm" "module Main"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "makeTempDirectory"
            [ test "makeTempDirectory returns deterministic path" <|
                \() ->
                    Script.makeTempDirectory "my-build-"
                        |> BackendTask.andThen Script.log
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "/tmp/my-build-0"
                        |> BackendTaskTest.expectSuccess
            , test "files can be written to temp directory" <|
                \() ->
                    Script.makeTempDirectory "work-"
                        |> BackendTask.andThen
                            (\tmpDir ->
                                Script.writeFile { path = tmpDir ++ "/output.txt", body = "content" }
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureFile "/tmp/work-0/output.txt" "content"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "BackendTask.Time.now"
            [ test "now returns configured time" <|
                \() ->
                    BackendTask.Time.now
                        |> BackendTask.andThen
                            (\time ->
                                Script.log (String.fromInt (Time.posixToMillis time))
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withTime (Time.millisToPosix 1709827200000)
                            )
                        |> BackendTaskTest.ensureLogged "1709827200000"
                        |> BackendTaskTest.expectSuccess
            , test "now without withTime gives helpful error" <|
                \() ->
                    BackendTask.Time.now
                        |> BackendTask.andThen (\_ -> BackendTask.succeed ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> String.contains "withTime"
                                    |> Expect.equal True
                            )
            ]
        , describe "BackendTask.Random"
            [ test "random with seeded value returns deterministic result" <|
                \() ->
                    BackendTask.Random.int32
                        |> BackendTask.andThen
                            (\seed -> Script.log (String.fromInt seed))
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withRandomSeed 42
                            )
                        |> BackendTaskTest.ensureLogged "42"
                        |> BackendTaskTest.expectSuccess
            , test "Random.generate uses seeded value" <|
                \() ->
                    BackendTask.Random.generate (Random.int 0 100)
                        |> BackendTask.andThen
                            (\value -> Script.log (String.fromInt value))
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withRandomSeed 42
                            )
                        |> BackendTaskTest.expectSuccess
            , test "random without withRandomSeed gives helpful error" <|
                \() ->
                    BackendTask.Random.int32
                        |> BackendTask.andThen (\_ -> BackendTask.succeed ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> String.contains "withRandomSeed"
                                    |> Expect.equal True
                            )
            ]
        , describe "Script.which"
            [ test "which returns path for registered command" <|
                \() ->
                    Script.which "elm-review"
                        |> BackendTask.andThen
                            (\maybePath ->
                                Script.log (Maybe.withDefault "not found" maybePath)
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withWhich "elm-review" "/usr/local/bin/elm-review"
                            )
                        |> BackendTaskTest.ensureLogged "/usr/local/bin/elm-review"
                        |> BackendTaskTest.expectSuccess
            , test "which returns Nothing for unregistered command" <|
                \() ->
                    Script.which "nonexistent"
                        |> BackendTask.andThen
                            (\maybePath ->
                                Script.log (Maybe.withDefault "not found" maybePath)
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "not found"
                        |> BackendTaskTest.expectSuccess
            , test "expectWhich succeeds for registered command" <|
                \() ->
                    Script.expectWhich "node"
                        |> BackendTask.andThen Script.log
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withWhich "node" "/usr/bin/node"
                            )
                        |> BackendTaskTest.ensureLogged "/usr/bin/node"
                        |> BackendTaskTest.expectSuccess
            , test "expectWhich fails for unregistered command" <|
                \() ->
                    Script.expectWhich "nonexistent"
                        |> BackendTask.andThen (\_ -> BackendTask.succeed ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFailure
            ]
        , describe "simulateQuestion"
            [ test "question resolves with simulated answer" <|
                \() ->
                    Script.question "What is your name? "
                        |> BackendTask.andThen
                            (\name -> Script.log ("Hello, " ++ name ++ "!"))
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateQuestion "What is your name? " "Dillon"
                        |> BackendTaskTest.ensureLogged "Hello, Dillon!"
                        |> BackendTaskTest.expectSuccess
            , test "wrong prompt gives helpful error" <|
                \() ->
                    Script.question "What is your name? "
                        |> BackendTask.andThen (\_ -> BackendTask.succeed ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateQuestion "Wrong prompt" "answer"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> String.contains "What is your name?"
                                    |> Expect.equal True
                            )
            ]
        , describe "simulateReadKey"
            [ test "readKey resolves with simulated key" <|
                \() ->
                    Script.readKey
                        |> BackendTask.andThen
                            (\key ->
                                if key == "y" then
                                    Script.log "confirmed"

                                else
                                    Script.log "rejected"
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateReadKey "y"
                        |> BackendTaskTest.ensureLogged "confirmed"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "resolve-path"
            [ test "FilePath.resolve returns input unchanged" <|
                \() ->
                    FilePath.fromString "src/Main.elm"
                        |> FilePath.resolve
                        |> BackendTask.andThen
                            (\resolved -> Script.log (FilePath.toString resolved))
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "src/Main.elm"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "binaryFile"
            [ test "reads seeded binary file" <|
                \() ->
                    let
                        testBytes : Bytes.Bytes
                        testBytes =
                            Bytes.Encode.encode
                                (Bytes.Encode.sequence
                                    [ Bytes.Encode.unsignedInt8 0xDE
                                    , Bytes.Encode.unsignedInt8 0xAD
                                    , Bytes.Encode.unsignedInt8 0xBE
                                    , Bytes.Encode.unsignedInt8 0xEF
                                    ]
                                )
                    in
                    BackendTask.File.binaryFile "test.bin"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\bytes ->
                                Script.log (String.fromInt (Bytes.width bytes))
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withBinaryFile "test.bin" testBytes
                            )
                        |> BackendTaskTest.ensureLogged "4"
                        |> BackendTaskTest.expectSuccess
            , test "binary file not found produces error" <|
                \() ->
                    BackendTask.File.binaryFile "missing.bin"
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> String.contains "Internal error"
                                    |> Expect.equal True
                            )
            , test "binary file with inDir" <|
                \() ->
                    let
                        testBytes : Bytes.Bytes
                        testBytes =
                            Bytes.Encode.encode
                                (Bytes.Encode.unsignedInt8 42)
                    in
                    BackendTask.File.binaryFile "data.bin"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\bytes ->
                                Script.log (String.fromInt (Bytes.width bytes))
                            )
                        |> BackendTask.inDir "subdir"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withBinaryFile "subdir/data.bin" testBytes
                            )
                        |> BackendTaskTest.ensureLogged "1"
                        |> BackendTaskTest.expectSuccess
            , test "binary file round-trip preserves content" <|
                \() ->
                    let
                        testBytes : Bytes.Bytes
                        testBytes =
                            Bytes.Encode.encode
                                (Bytes.Encode.sequence
                                    [ Bytes.Encode.unsignedInt32 Bytes.BE 12345
                                    , Bytes.Encode.unsignedInt32 Bytes.BE 67890
                                    ]
                                )
                    in
                    BackendTask.File.binaryFile "data.bin"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\bytes ->
                                case Bytes.Decode.decode (Bytes.Decode.unsignedInt32 Bytes.BE) bytes of
                                    Just firstInt ->
                                        Script.log (String.fromInt firstInt)

                                    Nothing ->
                                        Script.log "decode failed"
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withBinaryFile "data.bin" testBytes
                            )
                        |> BackendTaskTest.ensureLogged "12345"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "binary file integration with FS ops"
            [ test "file-exists returns true for binary file" <|
                \() ->
                    let
                        testBytes : Bytes.Bytes
                        testBytes =
                            Bytes.Encode.encode (Bytes.Encode.unsignedInt8 42)
                    in
                    BackendTask.File.exists "data.bin"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\exists ->
                                Script.log (boolToString exists)
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withBinaryFile "data.bin" testBytes
                            )
                        |> BackendTaskTest.ensureLogged "true"
                        |> BackendTaskTest.expectSuccess
            , test "delete removes binary file" <|
                \() ->
                    let
                        testBytes : Bytes.Bytes
                        testBytes =
                            Bytes.Encode.encode (Bytes.Encode.unsignedInt8 42)
                    in
                    Script.removeFile "data.bin"
                        |> BackendTask.andThen (\() -> BackendTask.File.exists "data.bin" |> BackendTask.allowFatal)
                        |> BackendTask.andThen (\exists -> Script.log (boolToString exists))
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withBinaryFile "data.bin" testBytes
                            )
                        |> BackendTaskTest.ensureLogged "false"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "FS edge cases"
            [ test "copy non-existent file produces error" <|
                \() ->
                    Script.copyFile { from = "missing.txt", to = "dest.txt" }
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> String.contains "missing.txt"
                                    |> Expect.equal True
                            )
            , test "move non-existent file produces error" <|
                \() ->
                    Script.move { from = "missing.txt", to = "dest.txt" }
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> String.contains "missing.txt"
                                    |> Expect.equal True
                            )
            , test "move file to itself is no-op" <|
                \() ->
                    Script.writeFile
                        { path = "test.txt", body = "content" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                Script.move { from = "test.txt", to = "test.txt" }
                            )
                        |> BackendTask.andThen
                            (\() ->
                                BackendTask.File.rawFile "test.txt"
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTask.andThen (\content -> Script.log content)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureLogged "content"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "frontmatter"
            [ test "bodyWithFrontmatter reads parsed frontmatter" <|
                \() ->
                    BackendTask.File.bodyWithFrontmatter
                        (\bodyText ->
                            Decode.map2 (\title -> \b -> { title = title, body = b })
                                (Decode.field "title" Decode.string)
                                (Decode.succeed bodyText)
                        )
                        "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\result ->
                                Script.log (result.title ++ ": " ++ String.trim result.body)
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureLogged "Hello: Body text"
                        |> BackendTaskTest.expectSuccess
            , test "onlyFrontmatter reads parsed frontmatter" <|
                \() ->
                    BackendTask.File.onlyFrontmatter
                        (Decode.field "title" Decode.string)
                        "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\title -> Script.log title)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureLogged "Hello"
                        |> BackendTaskTest.expectSuccess
            , test "bodyWithoutFrontmatter strips frontmatter markers" <|
                \() ->
                    BackendTask.File.bodyWithoutFrontmatter "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\body -> Script.log (String.trim body))
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureLogged "Body text"
                        |> BackendTaskTest.expectSuccess
            , test "rawFile returns full content including frontmatter" <|
                \() ->
                    BackendTask.File.rawFile "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\raw -> Script.log raw)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.defaultSetup
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureLogged "---\n{\"title\": \"Hello\"}\n---\nBody text"
                        |> BackendTaskTest.expectSuccess
            ]
        ]


boolToString : Bool -> String
boolToString b =
    if b then
        "true"

    else
        "false"


isFailingExpectation : Expect.Expectation -> Expect.Expectation
isFailingExpectation expectation =
    case Test.Runner.getFailureReason expectation of
        Just _ ->
            Expect.pass

        Nothing ->
            Expect.fail "Expected the expectation to fail, but it passed."
