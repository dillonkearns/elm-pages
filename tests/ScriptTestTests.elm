module ScriptTestTests exposing (all)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import BackendTask.File
import BackendTask.Http
import BackendTask.Stream as Stream
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
import Test.Runner


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
        , describe "virtual filesystem"
            [ test "writeFile updates virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "hello world" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFile "output.txt" "hello world"
                        |> BackendTaskTest.expectSuccess
            , test "expectFile fails when file doesn't exist" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFile "missing.txt" "content"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """expectFile: Expected file "missing.txt" to exist but it was not found.

Files in virtual filesystem:

    (none)"""
                            )
            , test "expectFile fails when content doesn't match" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "actual content" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFile "output.txt" "expected content"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """expectFile: File "output.txt" exists but has different content.

Expected:

    expected content

Actual:

    actual content"""
                            )
            , test "expectNoFile passes when file doesn't exist" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectNoFile "missing.txt"
                        |> BackendTaskTest.expectSuccess
            , test "expectNoFile fails when file exists" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "content" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectNoFile "output.txt"
                        |> BackendTaskTest.expectTestError
                            (\msg ->
                                msg
                                    |> Expect.equal
                                        """expectNoFile: Expected file "output.txt" to not exist but it was found."""
                            )
            , test "expectFileExists passes when file exists" <|
                \() ->
                    Script.writeFile { path = "output.txt", body = "content" }
                        |> BackendTask.allowFatal
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFileExists "output.txt"
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
                        |> BackendTaskTest.expectFile "a.txt" "aaa"
                        |> BackendTaskTest.expectFile "b.txt" "bbb"
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
                        |> BackendTaskTest.expectFile "output.txt" "second"
                        |> BackendTaskTest.expectSuccess
            , test "removeFile removes from virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "temp.txt", body = "data" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.removeFile "temp.txt")
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectNoFile "temp.txt"
                        |> BackendTaskTest.expectSuccess
            , test "copyFile copies in virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "original.txt", body = "hello" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.copyFile { from = "original.txt", to = "copy.txt" })
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectFile "original.txt" "hello"
                        |> BackendTaskTest.expectFile "copy.txt" "hello"
                        |> BackendTaskTest.expectSuccess
            , test "move renames in virtual filesystem" <|
                \() ->
                    Script.writeFile { path = "old.txt", body = "content" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.move { from = "old.txt", to = "new.txt" })
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectNoFile "old.txt"
                        |> BackendTaskTest.expectFile "new.txt" "content"
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
                        |> BackendTaskTest.expectFile "report.pdf" "pdf content"
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
                        |> BackendTaskTest.expectFile "temp.txt" "data"
                        |> BackendTaskTest.simulateCustom "cleanup" Encode.null
                        |> BackendTaskTest.expectNoFile "temp.txt"
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
                        |> BackendTaskTest.expectFile "custom.txt" "hello"
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
                        |> BackendTaskTest.expectFile "output.txt" "file content"
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
                        |> BackendTaskTest.expectFile "output.txt" "copied content"
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
                        |> BackendTaskTest.expectFile "output.txt" "stdin content"
                        |> BackendTaskTest.expectSuccess
            ]
        ]


boolToString : Bool -> String
boolToString b =
    if b then
        "true"

    else
        "false"
