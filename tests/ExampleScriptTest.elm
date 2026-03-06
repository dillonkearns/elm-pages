module ExampleScriptTest exposing (all)

import ExampleScript
import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test exposing (Test, describe, test)


all : Test
all =
    describe "ExampleScript"
        [ describe "fetchAndLogStars"
            [ test "fetches star count from GitHub API and logs it" <|
                \() ->
                    ExampleScript.fetchAndLogStars
                        { username = "dillonkearns", repo = "elm-pages" }
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.ensureHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 1205 ) ])
                        |> BackendTaskTest.ensureLogged "dillonkearns/elm-pages has 1205 stars"
                        |> BackendTaskTest.expectSuccess
            , test "works with a different repo" <|
                \() ->
                    ExampleScript.fetchAndLogStars
                        { username = "mdgriffith", repo = "elm-ui" }
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/mdgriffith/elm-ui"
                            (Encode.object [ ( "stargazers_count", Encode.int 1300 ) ])
                        |> BackendTaskTest.ensureLogged "mdgriffith/elm-ui has 1300 stars"
                        |> BackendTaskTest.expectSuccess
            ]
        , describe "fetchAndWriteReport"
            [ test "fetches stars for multiple repos and writes a report" <|
                \() ->
                    ExampleScript.fetchAndWriteReport
                        { username = "dillonkearns"
                        , repos = [ "elm-pages", "elm-graphql" ]
                        }
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Encode.object [ ( "stargazers_count", Encode.int 1205 ) ])
                        |> BackendTaskTest.simulateHttpGet
                            "https://api.github.com/repos/dillonkearns/elm-graphql"
                            (Encode.object [ ( "stargazers_count", Encode.int 780 ) ])
                        |> BackendTaskTest.ensureFileWritten
                            { path = "report.md"
                            , body = "# Star Report\n\nelm-pages: 1205\nelm-graphql: 780"
                            }
                        |> BackendTaskTest.expectSuccess
            ]
        ]
