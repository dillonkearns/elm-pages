module ScriptTestTests exposing (all)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.Http
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Script as Script
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest


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
        ]
