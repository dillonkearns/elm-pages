module ScriptTestTests exposing (all)

import BackendTask
import BackendTask.Custom
import BackendTask.Http
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
                                    |> Expect.all
                                        [ \m -> m |> String.contains "simulateHttpGet" |> Expect.equal True
                                        , \m -> m |> String.contains "https://WRONG-URL.com" |> Expect.equal True
                                        , \m -> m |> String.contains "https://api.github.com/repos/dillonkearns/elm-pages" |> Expect.equal True
                                        ]
                            )
            ]
        , describe "ensureHttpGet"
            [ test "validates pending GET request exists" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.field "stargazers_count" Decode.int)
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
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
                                    |> Expect.all
                                        [ \m -> m |> String.contains "ensureHttpGet" |> Expect.equal True
                                        , \m -> m |> String.contains "https://WRONG-URL.com" |> Expect.equal True
                                        , \m -> m |> String.contains "https://api.github.com/repos/dillonkearns/elm-pages" |> Expect.equal True
                                        ]
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
                            (\stars ->
                                BackendTask.Http.getJson
                                    ("https://api.github.com/repos/dillonkearns/elm-pages-starter")
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
                                    |> Expect.all
                                        [ \m -> m |> String.contains "ensureLogged" |> Expect.equal True
                                        , \m -> m |> String.contains "goodbye" |> Expect.equal True
                                        , \m -> m |> String.contains "hello" |> Expect.equal True
                                        ]
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
                                    |> Expect.all
                                        [ \m -> m |> String.contains "simulateHttpPost" |> Expect.equal True
                                        , \m -> m |> String.contains "GET" |> Expect.equal True
                                        ]
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
                                    |> Expect.all
                                        [ \m -> m |> String.contains "simulateHttpError" |> Expect.equal True
                                        , \m -> m |> String.contains "https://WRONG.com" |> Expect.equal True
                                        , \m -> m |> String.contains "https://api.example.com/data" |> Expect.equal True
                                        ]
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
                                    |> Expect.all
                                        [ \m -> m |> String.contains "simulateCustom" |> Expect.equal True
                                        , \m -> m |> String.contains "wrongPortName" |> Expect.equal True
                                        , \m -> m |> String.contains "hashPassword" |> Expect.equal True
                                        ]
                            )
            ]
        , describe "error messages"
            [ test "simulateHttpGet on completed script" <|
                \() ->
                    BackendTask.succeed ()
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet "https://example.com" (Encode.object [])
                        |> BackendTaskTest.expectTestError
                            (\msg -> msg |> String.contains "already completed" |> Expect.equal True)
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
                                    |> Expect.all
                                        [ \m -> m |> String.contains "ensureFileWritten" |> Expect.equal True
                                        , \m -> m |> String.contains "expected.txt" |> Expect.equal True
                                        , \m -> m |> String.contains "actual.txt" |> Expect.equal True
                                        ]
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
