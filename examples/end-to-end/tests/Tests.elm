module Tests exposing (suite)

import Expect
import PagesTest
import ProgramTest
import Test exposing (Test, describe, test)
import Test.Html.Selector exposing (text)


suite : Test
suite =
    describe "end to end tests"
        [ test "wire up hello" <|
            \() ->
                PagesTest.start "/greet?name=dillon" mockData
                    |> ProgramTest.expectViewHas
                        [ text "Hello dillon!"
                        ]
        , test "redirect then login" <|
            \() ->
                PagesTest.start "/login" mockData
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
                    |> ProgramTest.fillInDom "name" "Name" "Jane"
                    |> ProgramTest.submitForm
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
                    |> ProgramTest.ensureViewHas
                        [ text "Hello Jane!"
                        ]
                    |> ProgramTest.done
        , test "back to login page with session" <|
            \() ->
                PagesTest.start "/login" mockData
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
                    |> ProgramTest.fillInDom "name" "Name" "Jane"
                    |> ProgramTest.submitForm
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/greet")
                    |> ProgramTest.routeChange "/login"
                    |> ProgramTest.ensureBrowserUrl (Expect.equal "https://localhost:1234/login")
                    |> ProgramTest.ensureViewHas [ text "Hello Jane!" ]
                    |> ProgramTest.done
        ]


mockData : PagesTest.DataSourceSimulator
mockData _ _ _ request =
    Nothing
