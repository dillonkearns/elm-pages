module PlatformTests exposing (suite)

import Expect
import Pages.StaticHttp.Request
import RequestsAndPending
import Test exposing (Test, describe, test)
import Test.Html.Selector exposing (text)
import Test.PagesProgram as PagesProgram
import TestApp


suite : Test
suite =
    describe "Platform-based tests (real framework)"
        [ test "counter page renders through Shared layout" <|
            \() ->
                TestApp.start "/counter" mockData
                    |> PagesProgram.ensureViewHas [ text "Count: 0" ]
                    |> PagesProgram.done
        , test "hello page renders" <|
            \() ->
                TestApp.start "/hello" mockData
                    |> PagesProgram.ensureViewHas [ text "Hello" ]
                    |> PagesProgram.done
        , test "counter increment and decrement" <|
            \() ->
                TestApp.start "/counter" mockData
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.ensureViewHas [ text "Count: 3" ]
                    |> PagesProgram.clickButton "-"
                    |> PagesProgram.ensureViewHas [ text "Count: 2" ]
                    |> PagesProgram.done
        , test "navigate from links to counter" <|
            \() ->
                TestApp.start "/links" mockData
                    |> PagesProgram.ensureViewHas [ text "Links Page" ]
                    |> PagesProgram.clickLink "Go to Counter" "/counter"
                    |> PagesProgram.ensureViewHas [ text "Count: 0" ]
                    |> PagesProgram.done
        , test "navigate and then interact" <|
            \() ->
                TestApp.start "/links" mockData
                    |> PagesProgram.clickLink "Go to Counter" "/counter"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.ensureViewHas [ text "Count: 2" ]
                    |> PagesProgram.done
        , test "ensureBrowserUrl tracks navigation" <|
            \() ->
                TestApp.start "/links" mockData
                    |> PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/links")
                    |> PagesProgram.navigateTo "/counter"
                    |> PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/counter")
                    |> PagesProgram.done
        , test "fill in form and submit" <|
            \() ->
                TestApp.start "/feedback" mockData
                    |> PagesProgram.ensureViewHas [ text "Feedback Form" ]
                    |> PagesProgram.fillIn "feedback-form" "message" "Hello from tests!"
                    |> PagesProgram.clickButton "Submit Feedback"
                    |> PagesProgram.ensureViewHas [ text "You said: Hello from tests!" ]
                    |> PagesProgram.done
        ]


mockData : Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response
mockData request =
    Nothing
