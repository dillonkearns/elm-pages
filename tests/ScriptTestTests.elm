module ScriptTestTests exposing (all)

import BackendTask
import BackendTask.Http
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Script as Script
import ScriptTest
import Test exposing (Test, describe, test)


all : Test
all =
    describe "ScriptTest"
        [ describe "fromBackendTask + expectSuccess"
            [ test "succeeds for BackendTask.succeed ()" <|
                \() ->
                    BackendTask.succeed ()
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.expectSuccess
            ]
        , describe "simulateHttpGet"
            [ test "single HTTP GET resolves and succeeds" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.field "stargazers_count" Decode.int)
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> ScriptTest.expectSuccess
            , test "wrong URL gives helpful error" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.field "stargazers_count" Decode.int)
                        |> BackendTask.allowFatal
                        |> BackendTask.map (\_ -> ())
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.simulateHttpGet
                            "https://WRONG-URL.com"
                            (Encode.object [])
                        |> ScriptTest.expectTestError
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
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.ensureHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> ScriptTest.expectSuccess
            , test "fails when expected GET not pending" <|
                \() ->
                    BackendTask.Http.getJson
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Decode.succeed ())
                        |> BackendTask.allowFatal
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.ensureHttpGet "https://WRONG-URL.com"
                        |> ScriptTest.expectTestError
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
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                            (Encode.object [ ( "stargazers_count", Encode.int 22 ) ])
                        |> ScriptTest.expectSuccess
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
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                            (Encode.object [ ( "stargazers_count", Encode.int 22 ) ])
                        |> ScriptTest.expectSuccess
            ]
        , describe "auto-resolve and tracking"
            [ test "ensureLogged fails when message not present" <|
                \() ->
                    Script.log "hello"
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.ensureLogged "goodbye"
                        |> ScriptTest.expectTestError
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
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> ScriptTest.ensureLogged "86"
                        |> ScriptTest.expectSuccess
            ]
        , describe "file write tracking"
            [ test "writeFile auto-resolves and is tracked by ensureFileWritten" <|
                \() ->
                    Script.writeFile { path = "output.json", body = """{"key":"value"}""" }
                        |> BackendTask.allowFatal
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.ensureFileWritten { path = "output.json", body = """{"key":"value"}""" }
                        |> ScriptTest.expectSuccess
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
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> ScriptTest.ensureLogged "86"
                        |> ScriptTest.expectSuccess
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
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                        |> ScriptTest.ensureFileWritten { path = "stars.txt", body = "86" }
                        |> ScriptTest.expectSuccess
            ]
        , describe "fromBackendTask + expectFailure"
            [ test "fails for BackendTask.fail" <|
                \() ->
                    FatalError.fromString "Something went wrong"
                        |> BackendTask.fail
                        |> ScriptTest.fromBackendTask
                        |> ScriptTest.expectFailure
            ]
        ]
