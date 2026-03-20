module PlatformTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector exposing (text)
import Test.PagesProgram as PagesProgram
import TestApp


suite : Test
suite =
    describe "Platform-based tests (real framework)"
        [ test "counter page renders through Shared layout" <|
            \() ->
                TestApp.start "/counter" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ text "Count: 0" ]
                    |> PagesProgram.done
        , test "hello page renders" <|
            \() ->
                TestApp.start "/hello" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ text "Hello" ]
                    |> PagesProgram.done
        , test "counter increment and decrement" <|
            \() ->
                TestApp.start "/counter" BackendTaskTest.init
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.ensureViewHas [ text "Count: 3" ]
                    |> PagesProgram.clickButton "-"
                    |> PagesProgram.ensureViewHas [ text "Count: 2" ]
                    |> PagesProgram.done
        , test "navigate from links to counter" <|
            \() ->
                TestApp.start "/links" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ text "Links Page" ]
                    |> PagesProgram.clickLink "Go to Counter" "/counter"
                    |> PagesProgram.ensureViewHas [ text "Count: 0" ]
                    |> PagesProgram.done
        , test "navigate and then interact" <|
            \() ->
                TestApp.start "/links" BackendTaskTest.init
                    |> PagesProgram.clickLink "Go to Counter" "/counter"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.ensureViewHas [ text "Count: 2" ]
                    |> PagesProgram.done
        , test "ensureBrowserUrl tracks navigation" <|
            \() ->
                TestApp.start "/links" BackendTaskTest.init
                    |> PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/links")
                    |> PagesProgram.navigateTo "/counter"
                    |> PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/counter")
                    |> PagesProgram.done
        , test "form submit with file read/write data refresh" <|
            \() ->
                TestApp.start "/feedback"
                    (BackendTaskTest.init
                        |> BackendTaskTest.withFile "feedback.txt" "No messages yet"
                    )
                    |> PagesProgram.ensureViewHas [ text "Current file: No messages yet" ]
                    |> PagesProgram.fillIn "feedback-form" "message" "Hello!"
                    |> PagesProgram.clickButton "Submit Feedback"
                    -- Action wrote "Hello!" to feedback.txt.
                    -- Framework re-resolved data, which reads the updated file.
                    |> PagesProgram.ensureViewHas [ text "You said: Hello!" ]
                    |> PagesProgram.ensureViewHas [ text "Current file: Hello!" ]
                    |> PagesProgram.done
        ]
