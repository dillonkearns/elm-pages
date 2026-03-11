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
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Expect
import FatalError exposing (FatalError)
import FilePath
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Script as Script
import Random
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest exposing (Output(..))
import Test.BackendTask.Time as BackendTaskTime
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
            [ test "ensureStdout fails when message not present" <|
                \() ->
                    Script.log "hello"
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout [ "goodbye" ]
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                Expect.equal
                                    """ensureOutputWith: Output assertion failed.

Expect.equal

Output since last drain:

    stdout: "hello\""""
                                    msg
                            )
            , test "Script.log auto-resolves and is tracked by ensureStdout" <|
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
                        |> BackendTaskTest.ensureStdout [ "86" ]
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
                        |> BackendTaskTest.ensureStdout [ "86" ]
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
                            (\_ -> Expect.pass)
                        |> BackendTaskTest.simulateHttpGet "https://api.example.com/config" Encode.null
                        |> BackendTaskTest.simulateHttpPost
                            "https://api.example.com/items"
                            (Encode.object [ ( "id", Encode.int 42 ) ])
                        |> BackendTaskTest.expectSuccess
            , test "asserts on POST request body" <|
                \() ->
                    BackendTask.Http.post "https://api.example.com/items"
                        (BackendTask.Http.jsonBody
                            (Encode.object
                                [ ( "name", Encode.string "test-item" )
                                , ( "count", Encode.int 42 )
                                ]
                            )
                        )
                        (BackendTask.Http.expectJson (Decode.succeed ()))
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
                            (\body ->
                                case Decode.decodeValue (Decode.field "name" Decode.string) body of
                                    Ok name ->
                                        Expect.equal "test-item" name

                                    Err err ->
                                        Expect.fail (Decode.errorToString err)
                            )
                        |> BackendTaskTest.simulateHttpPost "https://api.example.com/items" Encode.null
                        |> BackendTaskTest.expectSuccess
            , test "fails when body assertion fails" <|
                \() ->
                    BackendTask.Http.post "https://api.example.com/items"
                        (BackendTask.Http.jsonBody (Encode.object [ ( "name", Encode.string "actual" ) ]))
                        (BackendTask.Http.expectJson (Decode.succeed ()))
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
                            (\body ->
                                Decode.decodeValue (Decode.field "name" Decode.string) body
                                    |> Expect.equal (Ok "expected")
                            )
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                String.contains "assertion failed" msg
                                    |> Expect.equal True
                            )
            , test "fails when expected POST not pending" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/items"
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
                            (\_ -> Expect.pass)
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
                        |> BackendTaskTest.ensureCustom "hashPassword" (\_ -> Expect.pass)
                        |> BackendTaskTest.ensureCustom "sendEmail" (\_ -> Expect.pass)
                        |> BackendTaskTest.simulateCustom "hashPassword"
                            (Encode.string "hashed_secret123")
                        |> BackendTaskTest.simulateCustom "sendEmail"
                            Encode.null
                        |> BackendTaskTest.expectSuccess
            , test "asserts on custom port arguments" <|
                \() ->
                    BackendTask.Custom.run "hashPassword"
                        (Encode.string "secret123")
                        Decode.string
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureCustom "hashPassword"
                            (\args ->
                                Decode.decodeValue Decode.string args
                                    |> Expect.equal (Ok "secret123")
                            )
                        |> BackendTaskTest.simulateCustom "hashPassword"
                            (Encode.string "hashed_secret123")
                        |> BackendTaskTest.expectSuccess
            , test "fails when argument assertion fails" <|
                \() ->
                    BackendTask.Custom.run "hashPassword"
                        (Encode.string "actual-value")
                        Decode.string
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureCustom "hashPassword"
                            (\args ->
                                Decode.decodeValue Decode.string args
                                    |> Expect.equal (Ok "expected-value")
                            )
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                String.contains "assertion failed" msg
                                    |> Expect.equal True
                            )
            , test "fails when expected port not pending" <|
                \() ->
                    BackendTask.Custom.run "hashPassword"
                        (Encode.string "secret123")
                        Decode.string
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureCustom "wrongPortName" (\_ -> Expect.pass)
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
                        |> BackendTaskTest.ensureStdout [ "hello" ]
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
                        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
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
                        |> BackendTaskTest.ensureStdout [ "Hello, world!" ]
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
                        |> BackendTaskTest.ensureStdout [ "Read: round-trip" ]
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
                        |> BackendTaskTest.ensureStdout [ "exists: true, missing: false" ]
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "withVirtualEffects"
            [ test "custom port writes file to virtual filesystem" <|
                \() ->
                    BackendTask.Custom.run "generateReport"
                        (Encode.string "input data")
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.withVirtualEffects
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
                        |> BackendTaskTest.withVirtualEffects
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
                        |> BackendTaskTest.withVirtualEffects
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
                        |> BackendTaskTest.ensureStdout [ "hello world" ]
                        |> BackendTaskTest.expectSuccess
            , test "fromString piped to stderr tracks output" <|
                \() ->
                    Stream.fromString "error message"
                        |> Stream.pipe Stream.stderr
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStderr [ "error message" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "data.txt" "seeded data"
                            )
                        |> BackendTaskTest.ensureStdout [ "seeded data" ]
                        |> BackendTaskTest.expectSuccess
            , test "fileRead piped to fileWrite copies via VFS" <|
                \() ->
                    Stream.fileRead "input.txt"
                        |> Stream.pipe (Stream.fileWrite "output.txt")
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
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
                        |> BackendTaskTest.ensureStdout [ "hello" ]
                        |> BackendTaskTest.expectSuccess
            , test "stream readJson returns parsed JSON" <|
                \() ->
                    Stream.fromString """{"name":"test"}"""
                        |> Stream.readJson (Decode.field "name" Decode.string)
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\{ body } -> Script.log body)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout [ "test" ]
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
                        |> BackendTaskTest.ensureStdout [ "written by stream" ]
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
                        |> BackendTaskTest.ensureStdout [ "written by script" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "config.json" """{"port":8080}"""
                            )
                        |> BackendTaskTest.ensureStdout [ """{"port":8080}""" ]
                        |> BackendTaskTest.expectSuccess
            , test "stdin reads seeded content" <|
                \() ->
                    Stream.stdin
                        |> Stream.read
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\{ body } -> Script.log body)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withStdin "hello from stdin"
                            )
                        |> BackendTaskTest.ensureStdout [ "hello from stdin" ]
                        |> BackendTaskTest.expectSuccess
            , test "stdin piped to stdout" <|
                \() ->
                    Stream.stdin
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withStdin "piped through"
                            )
                        |> BackendTaskTest.ensureStdout [ "piped through" ]
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
                            (BackendTaskTest.init
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
                        |> BackendTaskTest.ensureStdout [ "42" ]
                        |> BackendTaskTest.expectSuccess
            , test "fileRead before command reads from VFS" <|
                \() ->
                    Stream.fileRead "data.txt"
                        |> Stream.pipe (Stream.command "grep" [ "error" ])
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "data.txt" "line1\nerror: bad\nline3"
                            )
                        |> BackendTaskTest.simulateCommand "grep" "error: bad\n"
                        |> BackendTaskTest.ensureStdout [ "error: bad\n" ]
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
                            (BackendTaskTest.init
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
                        |> BackendTaskTest.ensureStdout [ "file1.txt\nfile2.txt" ]
                        |> BackendTaskTest.expectSuccess
            , test "command with withVirtualEffects writes to VFS" <|
                \() ->
                    Script.exec "elm" [ "make", "--docs=docs.json" ]
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.withVirtualEffects
                            (\name body ->
                                case name of
                                    "elm" ->
                                        let
                                            args : List String
                                            args =
                                                Decode.decodeValue (Decode.list Decode.string) body
                                                    |> Result.withDefault []

                                            docsPath : Maybe String
                                            docsPath =
                                                args
                                                    |> List.filterMap
                                                        (\arg ->
                                                            if String.startsWith "--docs=" arg then
                                                                Just (String.dropLeft 7 arg)

                                                            else
                                                                Nothing
                                                        )
                                                    |> List.head
                                        in
                                        case docsPath of
                                            Just path ->
                                                [ BackendTaskTest.writeFileEffect path "{\"docs\":true}" ]

                                            Nothing ->
                                                []

                                    _ ->
                                        []
                            )
                        |> BackendTaskTest.simulateCommand "elm" ""
                        |> BackendTaskTest.ensureFile "docs.json" "{\"docs\":true}"
                        |> BackendTaskTest.expectSuccess
            , test "command with withVirtualEffects removes file from VFS" <|
                \() ->
                    Script.exec "rm" [ "temp.txt" ]
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "temp.txt" "data"
                            )
                        |> BackendTaskTest.withVirtualEffects
                            (\name _ ->
                                case name of
                                    "rm" ->
                                        [ BackendTaskTest.removeFileEffect "temp.txt" ]

                                    _ ->
                                        []
                            )
                        |> BackendTaskTest.ensureFile "temp.txt" "data"
                        |> BackendTaskTest.simulateCommand "rm" ""
                        |> BackendTaskTest.ensureNoFile "temp.txt"
                        |> BackendTaskTest.expectSuccess
            , test "ensureCommand checks args before simulation" <|
                \() ->
                    Script.exec "elm" [ "make", "--docs=docs.json" ]
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureCommand "elm"
                            (\args -> Expect.equal [ "make", "--docs=docs.json" ] args)
                        |> BackendTaskTest.simulateCommand "elm" ""
                        |> BackendTaskTest.expectSuccess
            , test "ensureCommand fails when args don't match" <|
                \() ->
                    Script.exec "elm" [ "make", "--output=/dev/null" ]
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureCommand "elm"
                            (\args -> Expect.equal [ "make", "--docs=docs.json" ] args)
                        |> BackendTaskTest.simulateCommand "elm" ""
                        |> BackendTaskTest.expectSuccess
                        |> isFailingExpectation
            , test "ensureCommand with wrong name gives helpful error" <|
                \() ->
                    Script.exec "elm" [ "make" ]
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureCommand "grep"
                            (\_ -> Expect.pass)
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> String.contains "grep"
                                    |> Expect.equal True
                            )
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
                        |> BackendTaskTest.ensureStdout [ "hello world" ]
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
                        |> BackendTaskTest.ensureStdout [ "secret" ]
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
                        |> BackendTaskTest.simulateHttpStream "https://api.example.com/data" "response body"
                        |> BackendTaskTest.ensureStdout [ "response body" ]
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
                        |> BackendTaskTest.simulateHttpStream "https://api.example.com/data" "{\"count\": 42}"
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
                        |> BackendTaskTest.simulateHttpStream "https://wrong.url/data" "response"
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withEnv "API_KEY" "secret123"
                            )
                        |> BackendTaskTest.ensureStdout [ "secret123" ]
                        |> BackendTaskTest.expectSuccess
            , test "Env.get returns Nothing for missing variable" <|
                \() ->
                    BackendTask.Env.get "MISSING_VAR"
                        |> BackendTask.andThen
                            (\maybeKey ->
                                Script.log (Maybe.withDefault "not set" maybeKey)
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout [ "not set" ]
                        |> BackendTaskTest.expectSuccess
            , test "Env.expect succeeds with seeded value" <|
                \() ->
                    BackendTask.Env.expect "DB_URL"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\url -> Script.log url)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withEnv "DB_URL" "postgres://localhost/mydb"
                            )
                        |> BackendTaskTest.ensureStdout [ "postgres://localhost/mydb" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withEnv "HOST" "localhost"
                                |> BackendTaskTest.withEnv "PORT" "3000"
                            )
                        |> BackendTaskTest.ensureStdout [ "localhost:3000" ]
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
                        |> BackendTaskTest.ensureStdout [ "injected" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withEnv "MY_VAR" "original"
                            )
                        |> BackendTaskTest.ensureStdout [ "overridden" ]
                        |> BackendTaskTest.expectSuccess
            , test "Env.expect works with BackendTask.withEnv" <|
                \() ->
                    BackendTask.Env.expect "REQUIRED_VAR"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen Script.log
                        |> BackendTask.withEnv "REQUIRED_VAR" "provided"
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout [ "provided" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "subdir/config.json" "found it"
                            )
                        |> BackendTaskTest.ensureStdout [ "found it" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "outer/inner/data.txt" "nested"
                            )
                        |> BackendTaskTest.ensureStdout [ "nested" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "subdir/config.json" "content"
                            )
                        |> BackendTaskTest.ensureStdout [ "true" ]
                        |> BackendTaskTest.expectSuccess
            , test "stream fileRead resolves relative to inDir" <|
                \() ->
                    Stream.fileRead "input.txt"
                        |> Stream.pipe Stream.stdout
                        |> Stream.run
                        |> BackendTask.inDir "mydir"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "mydir/input.txt" "stream content"
                            )
                        |> BackendTaskTest.ensureStdout [ "stream content" ]
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
                            (BackendTaskTest.init
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
                            (BackendTaskTest.init
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
                            (BackendTaskTest.init
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
                            (BackendTaskTest.init
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
                            (BackendTaskTest.init
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
                            (BackendTaskTest.init
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
                            (BackendTaskTest.init
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
                        |> BackendTaskTest.ensureStdout [ "after sleep" ]
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "makeDirectory"
            [ test "makeDirectory auto-resolves as no-op" <|
                \() ->
                    Script.makeDirectory { recursive = True } "dist/assets"
                        |> BackendTask.andThen (\() -> Script.log "dir created")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout [ "dir created" ]
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
                        |> BackendTaskTest.ensureStdout [ "removed" ]
                        |> BackendTaskTest.expectSuccess
            , test "removeDirectory removes matching files from VFS" <|
                \() ->
                    Script.removeDirectory { recursive = True } "build"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
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
                        |> BackendTaskTest.ensureStdout [ "/tmp/my-build-0" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withTime (Time.millisToPosix 1709827200000)
                            )
                        |> BackendTaskTest.ensureStdout [ "1709827200000" ]
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
        , describe "BackendTask.Time.zone"
            [ test "zone returns configured UTC timezone" <|
                \() ->
                    BackendTask.Time.zone
                        |> BackendTask.andThen
                            (\z ->
                                -- Jan 1, 2024 00:00 UTC with UTC zone should give hour 0
                                Script.log (String.fromInt (Time.toHour z (Time.millisToPosix 1704067200000)))
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTime.withTimeZone BackendTaskTime.utc
                            )
                        |> BackendTaskTest.ensureStdout [ "0" ]
                        |> BackendTaskTest.expectSuccess
            , test "zone returns configured fixed offset timezone" <|
                \() ->
                    BackendTask.Time.zone
                        |> BackendTask.andThen
                            (\z ->
                                -- Jan 1, 2024 00:00 UTC with UTC-5 gives hour 19 of Dec 31
                                Script.log (String.fromInt (Time.toHour z (Time.millisToPosix 1704067200000)))
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTime.withTimeZone (BackendTaskTime.fixedOffsetZone -300)
                            )
                        |> BackendTaskTest.ensureStdout [ "19" ]
                        |> BackendTaskTest.expectSuccess
            , test "zoneFor returns same zone (DateRange is ignored in tests)" <|
                \() ->
                    BackendTask.Time.zoneFor (BackendTask.Time.withinYears 5)
                        |> BackendTask.andThen
                            (\z ->
                                Script.log (String.fromInt (Time.toHour z (Time.millisToPosix 1704067200000)))
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTime.withTimeZone BackendTaskTime.utc
                            )
                        |> BackendTaskTest.ensureStdout [ "0" ]
                        |> BackendTaskTest.expectSuccess
            , test "zone without withTimeZone gives helpful error" <|
                \() ->
                    BackendTask.Time.zone
                        |> BackendTask.andThen (\_ -> BackendTask.succeed ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectTestError
                            (Expect.equal
                                ("BackendTask.Time.zone requires a virtual timezone.\n\n"
                                    ++ "Use withTimeZone in your TestSetup:\n\n"
                                    ++ "    BackendTaskTest.init\n"
                                    ++ "        |> BackendTaskTime.withTimeZone BackendTaskTime.utc"
                                )
                            )
            , test "zoneByName returns configured named timezone" <|
                \() ->
                    BackendTask.Time.zoneByName "America/Chicago"
                        |> BackendTask.andThen
                            (\z ->
                                -- Jan 1, 2024 00:00 UTC with UTC-6 gives hour 18 of Dec 31
                                Script.log (String.fromInt (Time.toHour z (Time.millisToPosix 1704067200000)))
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTime.withTimeZoneByName "America/Chicago"
                                    (BackendTaskTime.fixedOffsetZone -360)
                            )
                        |> BackendTaskTest.ensureStdout [ "18" ]
                        |> BackendTaskTest.expectSuccess
            , test "zoneByName without withTimeZoneByName gives helpful error" <|
                \() ->
                    BackendTask.Time.zoneByName "America/New_York"
                        |> BackendTask.andThen (\_ -> BackendTask.succeed ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectTestError
                            (Expect.equal
                                ("BackendTask.Time.zoneByName \"America/New_York\" requires a virtual timezone.\n\n"
                                    ++ "Use withTimeZoneByName in your TestSetup:\n\n"
                                    ++ "    BackendTaskTest.init\n"
                                    ++ "        |> BackendTaskTime.withTimeZoneByName \"America/New_York\"\n"
                                    ++ "            (BackendTaskTime.fixedOffsetZone -300)"
                                )
                            )
            , test "customTimeZone with DST eras works" <|
                \() ->
                    BackendTask.Time.zone
                        |> BackendTask.andThen
                            (\z ->
                                let
                                    -- Mar 10, 2024 08:00 UTC (after spring forward)
                                    summerHour : Int
                                    summerHour =
                                        Time.toHour z (Time.millisToPosix 1710057600000)

                                    -- Jan 1, 2024 00:00 UTC (winter, before spring forward)
                                    winterHour : Int
                                    winterHour =
                                        Time.toHour z (Time.millisToPosix 1704067200000)
                                in
                                Script.log (String.fromInt winterHour ++ "," ++ String.fromInt summerHour)
                            )
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTime.withTimeZone
                                    (BackendTaskTime.customTimeZone -300
                                        [ { start = 28500900, offset = -240 } -- Mar 10, 2024 07:00 UTC -> EDT
                                        ]
                                    )
                            )
                        |> BackendTaskTest.ensureStdout [ "19,4" ]
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "BackendTask.Random"
            [ test "random with seeded value returns deterministic result" <|
                \() ->
                    BackendTask.Random.int32
                        |> BackendTask.andThen
                            (\seed -> Script.log (String.fromInt seed))
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withRandomSeed 42
                            )
                        |> BackendTaskTest.ensureStdout [ "42" ]
                        |> BackendTaskTest.expectSuccess
            , test "Random.generate uses seeded value" <|
                \() ->
                    BackendTask.Random.generate (Random.int 0 100)
                        |> BackendTask.andThen
                            (\value -> Script.log (String.fromInt value))
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withWhich "elm-review" "/usr/local/bin/elm-review"
                            )
                        |> BackendTaskTest.ensureStdout [ "/usr/local/bin/elm-review" ]
                        |> BackendTaskTest.expectSuccess
            , test "which returns Nothing for unregistered command" <|
                \() ->
                    Script.which "nonexistent"
                        |> BackendTask.andThen
                            (\maybePath ->
                                Script.log (Maybe.withDefault "not found" maybePath)
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout [ "not found" ]
                        |> BackendTaskTest.expectSuccess
            , test "expectWhich succeeds for registered command" <|
                \() ->
                    Script.expectWhich "node"
                        |> BackendTask.andThen Script.log
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withWhich "node" "/usr/bin/node"
                            )
                        |> BackendTaskTest.ensureStdout [ "/usr/bin/node" ]
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
                        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
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
                        |> BackendTaskTest.ensureStdout [ "confirmed" ]
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
                        |> BackendTaskTest.ensureStdout [ "src/Main.elm" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withBinaryFile "test.bin" testBytes
                            )
                        |> BackendTaskTest.ensureStdout [ "4" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withBinaryFile "subdir/data.bin" testBytes
                            )
                        |> BackendTaskTest.ensureStdout [ "1" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withBinaryFile "data.bin" testBytes
                            )
                        |> BackendTaskTest.ensureStdout [ "12345" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withBinaryFile "data.bin" testBytes
                            )
                        |> BackendTaskTest.ensureStdout [ "true" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withBinaryFile "data.bin" testBytes
                            )
                        |> BackendTaskTest.ensureStdout [ "false" ]
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
                        |> BackendTaskTest.ensureStdout [ "content" ]
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureStdout [ "Hello: Body text" ]
                        |> BackendTaskTest.expectSuccess
            , test "onlyFrontmatter reads parsed frontmatter" <|
                \() ->
                    BackendTask.File.onlyFrontmatter
                        (Decode.field "title" Decode.string)
                        "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\title -> Script.log title)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureStdout [ "Hello" ]
                        |> BackendTaskTest.expectSuccess
            , test "bodyWithoutFrontmatter strips frontmatter markers" <|
                \() ->
                    BackendTask.File.bodyWithoutFrontmatter "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\body -> Script.log (String.trim body))
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureStdout [ "Body text" ]
                        |> BackendTaskTest.expectSuccess
            , test "rawFile returns full content including frontmatter" <|
                \() ->
                    BackendTask.File.rawFile "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\raw -> Script.log raw)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureStdout [ "---\n{\"title\": \"Hello\"}\n---\nBody text" ]
                        |> BackendTaskTest.expectSuccess
            , test "YAML frontmatter parses simple key-value" <|
                \() ->
                    BackendTask.File.onlyFrontmatter
                        (Decode.field "title" Decode.string)
                        "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\title -> Script.log title)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\ntitle: Hello\ntags:\n  - elm\n---\nBody"
                            )
                        |> BackendTaskTest.ensureStdout [ "Hello" ]
                        |> BackendTaskTest.expectSuccess
            , test "YAML frontmatter parses list field" <|
                \() ->
                    BackendTask.File.onlyFrontmatter
                        (Decode.field "tags" (Decode.list Decode.string))
                        "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\tags -> Script.log (String.join ", " tags))
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\ntitle: Hello\ntags:\n  - elm\n  - haskell\n---\nBody"
                            )
                        |> BackendTaskTest.ensureStdout [ "elm, haskell" ]
                        |> BackendTaskTest.expectSuccess
            , test "YAML frontmatter with int and bool values" <|
                \() ->
                    BackendTask.File.onlyFrontmatter
                        (Decode.map2 (\p d -> String.fromInt p ++ " " ++ boolToString d)
                            (Decode.field "port" Decode.int)
                            (Decode.field "debug" Decode.bool)
                        )
                        "config.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen Script.log
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "config.md" "---\nport: 3000\ndebug: true\n---\n"
                            )
                        |> BackendTaskTest.ensureStdout [ "3000 true" ]
                        |> BackendTaskTest.expectSuccess
            , test "YAML frontmatter with nested mapping" <|
                \() ->
                    BackendTask.File.onlyFrontmatter
                        (Decode.at [ "author", "name" ] Decode.string)
                        "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen Script.log
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\nauthor:\n  name: Dillon\n  url: https://example.com\n---\nBody"
                            )
                        |> BackendTaskTest.ensureStdout [ "Dillon" ]
                        |> BackendTaskTest.expectSuccess
            , test "YAML frontmatter with bodyWithFrontmatter" <|
                \() ->
                    BackendTask.File.bodyWithFrontmatter
                        (\bodyText ->
                            Decode.map2 (\title b -> title ++ ": " ++ String.trim b)
                                (Decode.field "title" Decode.string)
                                (Decode.succeed bodyText)
                        )
                        "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen Script.log
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\ntitle: My Post\n---\nHello world"
                            )
                        |> BackendTaskTest.ensureStdout [ "My Post: Hello world" ]
                        |> BackendTaskTest.expectSuccess
            , test "JSON frontmatter still works" <|
                \() ->
                    BackendTask.File.onlyFrontmatter
                        (Decode.field "title" Decode.string)
                        "post.md"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen Script.log
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\n{\"title\": \"Hello\"}\n---\nBody text"
                            )
                        |> BackendTaskTest.ensureStdout [ "Hello" ]
                        |> BackendTaskTest.expectSuccess
            , test "frontmatter with Windows line endings" <|
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
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "post.md" "---\u{000D}\n{\"title\": \"Hello\"}\u{000D}\n---\u{000D}\nBody text"
                            )
                        |> BackendTaskTest.ensureStdout [ "Hello: Body text" ]
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "simulateHttp"
            [ test "simulate 404 error response" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/users/999"
                        (Decode.field "name" Decode.string)
                        |> BackendTask.mapError .recoverable
                        |> BackendTask.onError
                            (\err ->
                                case err of
                                    BackendTask.Http.BadStatus { statusCode } _ ->
                                        if statusCode == 404 then
                                            BackendTask.succeed "not found"

                                        else
                                            BackendTask.succeed ("unexpected status: " ++ String.fromInt statusCode)

                                    _ ->
                                        BackendTask.succeed "other error"
                            )
                        |> BackendTask.andThen (\msg -> Script.log msg)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttp
                            { method = "GET", url = "https://api.example.com/users/999" }
                            { statusCode = 404
                            , statusText = "Not Found"
                            , headers = []
                            , body = Encode.object [ ( "error", Encode.string "User not found" ) ]
                            }
                        |> BackendTaskTest.ensureStdout [ "not found" ]
                        |> BackendTaskTest.expectSuccess
            , test "simulate PUT request" <|
                \() ->
                    BackendTask.Http.request
                        { url = "https://api.example.com/items/123"
                        , method = "PUT"
                        , headers = []
                        , body =
                            BackendTask.Http.jsonBody
                                (Encode.object [ ( "name", Encode.string "updated" ) ])
                        , retries = Nothing
                        , timeoutInMs = Nothing
                        }
                        (BackendTask.Http.expectJson (Decode.field "id" Decode.string))
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\id -> Script.log ("updated: " ++ id))
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttp
                            { method = "PUT", url = "https://api.example.com/items/123" }
                            { statusCode = 200
                            , statusText = "OK"
                            , headers = []
                            , body = Encode.object [ ( "id", Encode.string "123" ) ]
                            }
                        |> BackendTaskTest.ensureStdout [ "updated: 123" ]
                        |> BackendTaskTest.expectSuccess
            , test "simulate DELETE request" <|
                \() ->
                    BackendTask.Http.request
                        { url = "https://api.example.com/items/456"
                        , method = "DELETE"
                        , headers = []
                        , body = BackendTask.Http.emptyBody
                        , retries = Nothing
                        , timeoutInMs = Nothing
                        }
                        (BackendTask.Http.expectWhatever ())
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.log "deleted")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttp
                            { method = "DELETE", url = "https://api.example.com/items/456" }
                            { statusCode = 204
                            , statusText = "No Content"
                            , headers = []
                            , body = Encode.null
                            }
                        |> BackendTaskTest.ensureStdout [ "deleted" ]
                        |> BackendTaskTest.expectSuccess
            , test "simulate response with custom headers" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/data"
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.log "ok")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttp
                            { method = "GET", url = "https://api.example.com/data" }
                            { statusCode = 200
                            , statusText = "OK"
                            , headers = [ ( "x-request-id", "abc123" ) ]
                            , body = Encode.null
                            }
                        |> BackendTaskTest.ensureStdout [ "ok" ]
                        |> BackendTaskTest.expectSuccess
            , test "simulate 500 server error" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.example.com/data"
                        (Decode.field "value" Decode.string)
                        |> BackendTask.mapError .recoverable
                        |> BackendTask.onError
                            (\err ->
                                case err of
                                    BackendTask.Http.BadStatus { statusCode } _ ->
                                        BackendTask.succeed ("server error: " ++ String.fromInt statusCode)

                                    _ ->
                                        BackendTask.succeed "other error"
                            )
                        |> BackendTask.andThen (\msg -> Script.log msg)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttp
                            { method = "GET", url = "https://api.example.com/data" }
                            { statusCode = 500
                            , statusText = "Internal Server Error"
                            , headers = []
                            , body = Encode.object [ ( "error", Encode.string "Something broke" ) ]
                            }
                        |> BackendTaskTest.ensureStdout [ "server error: 500" ]
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "glob sorting"
            [ test "glob results are sorted without explicit List.sort" <|
                \() ->
                    Glob.fromString "*.txt"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "zebra.txt" ""
                                |> BackendTaskTest.withFile "apple.txt" ""
                                |> BackendTaskTest.withFile "mango.txt" ""
                            )
                        |> BackendTaskTest.expectSuccessWith
                            (Expect.equal
                                [ "apple.txt"
                                , "mango.txt"
                                , "zebra.txt"
                                ]
                            )
            ]
        , describe "path normalization"
            [ test "resolves dot-slash in file path" <|
                \() ->
                    BackendTask.File.rawFile "./hello.txt"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\content -> Script.log content)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "hello.txt" "world"
                            )
                        |> BackendTaskTest.ensureStdout [ "world" ]
                        |> BackendTaskTest.expectSuccess
            , test "resolves dot-dot in file path" <|
                \() ->
                    BackendTask.File.rawFile "foo/../hello.txt"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\content -> Script.log content)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "hello.txt" "world"
                            )
                        |> BackendTaskTest.ensureStdout [ "world" ]
                        |> BackendTaskTest.expectSuccess
            , test "resolves double slashes in file path" <|
                \() ->
                    BackendTask.File.rawFile "foo//bar.txt"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\content -> Script.log content)
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "foo/bar.txt" "content"
                            )
                        |> BackendTaskTest.ensureStdout [ "content" ]
                        |> BackendTaskTest.expectSuccess
            , test "write with dot-slash then read normalized" <|
                \() ->
                    Script.writeFile { path = "./output.txt", body = "result" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                BackendTask.File.rawFile "output.txt"
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTask.andThen (\content -> Script.log content)
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout [ "result" ]
                        |> BackendTaskTest.expectSuccess
            , test "inDir with dot-dot resolves correctly" <|
                \() ->
                    BackendTask.File.rawFile "../hello.txt"
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\content -> Script.log content)
                        |> BackendTask.inDir "subdir"
                        |> BackendTaskTest.fromBackendTaskWith
                            (BackendTaskTest.init
                                |> BackendTaskTest.withFile "hello.txt" "world"
                            )
                        |> BackendTaskTest.ensureStdout [ "world" ]
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "ensureOutputWith"
            [ test "gives all output messages to assertion" <|
                \() ->
                    Script.log "hello"
                        |> BackendTask.andThen (\() -> Script.log "world")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureOutputWith
                            (\outputs -> Expect.equal [ Stdout "hello", Stdout "world" ] outputs)
                        |> BackendTaskTest.expectSuccess
            , test "drains on success — second call only sees new output" <|
                \() ->
                    Script.log "phase1"
                        |> BackendTask.andThen (\() -> Script.log "phase1b")
                        |> BackendTask.andThen
                            (\() ->
                                BackendTask.Http.getJson
                                    "https://api.example.com/data"
                                    (Decode.succeed ())
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTask.andThen (\() -> Script.log "phase2")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureOutputWith
                            (\outputs -> Expect.equal [ Stdout "phase1", Stdout "phase1b" ] outputs)
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.example.com/data"
                            (Encode.object [])
                        |> BackendTaskTest.ensureOutputWith
                            (\outputs -> Expect.equal [ Stdout "phase2" ] outputs)
                        |> BackendTaskTest.expectSuccess
            , test "empty list when no new output since last drain" <|
                \() ->
                    Script.log "only one"
                        |> BackendTask.andThen
                            (\() ->
                                BackendTask.Http.getJson
                                    "https://api.example.com/data"
                                    (Decode.succeed ())
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTask.map (\() -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureOutputWith
                            (\outputs -> Expect.equal [ Stdout "only one" ] outputs)
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.example.com/data"
                            (Encode.object [])
                        |> BackendTaskTest.ensureOutputWith
                            (\outputs -> Expect.equal [] outputs)
                        |> BackendTaskTest.expectSuccess
            , test "does NOT drain on failure — output preserved for retry" <|
                \() ->
                    Script.log "important"
                        |> BackendTaskTest.fromBackendTask
                        -- This assertion fails (wrong expected value)...
                        |> BackendTaskTest.ensureOutputWith
                            (\outputs -> Expect.equal [ Stdout "wrong" ] outputs)
                        -- ...so it becomes a TestError.
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                Expect.equal
                                    """ensureOutputWith: Output assertion failed.

Expect.equal

Output since last drain:

    stdout: "important\""""
                                    msg
                            )
            , test "preserves interleaved stdout/stderr ordering" <|
                \() ->
                    Script.log "step 1"
                        |> BackendTask.andThen
                            (\() ->
                                Stream.fromString "warning!"
                                    |> Stream.pipe Stream.stderr
                                    |> Stream.run
                            )
                        |> BackendTask.andThen (\() -> Script.log "step 2")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureOutputWith
                            (\outputs ->
                                Expect.equal
                                    [ Stdout "step 1"
                                    , Stderr "warning!"
                                    , Stdout "step 2"
                                    ]
                                    outputs
                            )
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "ensureStdout/ensureStderr implicit assertions"
            [ test "ensureStdout fails when stderr is present" <|
                \() ->
                    Script.log "hello"
                        |> BackendTask.andThen
                            (\() ->
                                Stream.fromString "oops"
                                    |> Stream.pipe Stream.stderr
                                    |> Stream.run
                            )
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStdout [ "hello" ]
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                Expect.equal
                                    """ensureOutputWith: Output assertion failed.

ensureStdout found unexpected stderr output:

    "oops"

Use ensureOutputWith to check both stdout and stderr together.

Output since last drain:

    stdout: "hello"
    stderr: "oops\""""
                                    msg
                            )
            , test "ensureStderr fails when stdout is present" <|
                \() ->
                    Stream.fromString "error!"
                        |> Stream.pipe Stream.stderr
                        |> Stream.run
                        |> BackendTask.andThen (\() -> Script.log "logged")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureStderr [ "error!" ]
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                Expect.equal
                                    """ensureOutputWith: Output assertion failed.

ensureStderr found unexpected stdout output:

    "logged"

Use ensureOutputWith to check both stdout and stderr together.

Output since last drain:

    stderr: "error!"
    stdout: "logged\""""
                                    msg
                            )
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
