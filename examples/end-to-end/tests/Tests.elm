module Tests exposing (suite)

import Effect exposing (Effect)
import Expect
import Json.Decode as Decode
import PagesTest
import ProgramTest
import SimulatedEffect.Cmd
import SimulatedEffect.Http as Http
import Test exposing (Test, describe, test)
import Test.Html.Selector exposing (text)
import Test.Http


suite : Test
suite =
    describe "end to end tests"
        [ test "wire up hello" <|
            \() ->
                PagesTest.start "/greet?name=dillon" simulate mockData
                    |> ProgramTest.expectViewHas
                        [ text "Hello dillon!"
                        ]
        , test "redirect then login" <|
            \() ->
                PagesTest.start "/login" simulate mockData
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
                    |> ProgramTest.fillInDom "name" "Name" "Jane"
                    |> ProgramTest.clickButton "Login"
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
                    |> ProgramTest.ensureViewHas
                        [ text "Hello Jane!"
                        ]
                    |> ProgramTest.done
        , test "back to login page with session" <|
            \() ->
                PagesTest.start "/login" simulate mockData
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
                    |> ProgramTest.fillInDom "name" "Name" "Jane"
                    |> ProgramTest.clickButton "Login"
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
                    |> ProgramTest.routeChange "/login"
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
                    |> ProgramTest.ensureViewHas [ text "Hello Jane!" ]
                    |> ProgramTest.done
        , test "user effect simulation" <|
            \() ->
                PagesTest.start "/counter" simulate mockData
                    |> ProgramTest.ensureViewHas [ text "Loading..." ]
                    |> ProgramTest.simulateHttpResponse "GET"
                        "https://api.github.com/repos/dillonkearns/elm-pages"
                        (Test.Http.httpResponse
                            { body = """{"stargazers_count": 123}"""
                            , headers = []
                            , statusCode = 200
                            }
                        )
                    |> ProgramTest.ensureViewHas [ text "The count is: 123" ]
                    |> ProgramTest.done
        ]


mockData : PagesTest.BackendTaskSimulator
mockData _ _ _ request =
    Nothing


simulate : (a -> b) -> Effect a -> ProgramTest.SimulatedEffect b
simulate fromPageMsg effect =
    case effect of
        Effect.None ->
            SimulatedEffect.Cmd.none

        Effect.Cmd cmd ->
            SimulatedEffect.Cmd.none

        Effect.Batch effects ->
            effects
                |> List.map (simulate fromPageMsg)
                |> SimulatedEffect.Cmd.batch

        Effect.GetStargazers toMsg ->
            Http.get
                { url = "https://api.github.com/repos/dillonkearns/elm-pages"
                , expect =
                    Http.expectJson (toMsg >> fromPageMsg)
                        (Decode.field "stargazers_count" Decode.int)
                }
