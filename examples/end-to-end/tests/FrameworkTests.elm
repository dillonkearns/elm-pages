module FrameworkTests exposing
    ( counterClicksTest
    , navigationTest
    , navigateAndInteractTest
    , feedbackFormTest
    )

{-| Framework-driven route tests using the real elm-pages Platform.
These tests drive Pages.Internal.Platform directly, so shared layout,
navigation, form submission, and all framework behavior works identically
to production.

View in browser: elm-pages test-view tests/FrameworkTests.elm
-}

import Expect
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector exposing (text)
import Test.PagesProgram as PagesProgram
import TestApp


counterClicksTest : TestApp.ProgramTest
counterClicksTest =
    TestApp.start "/counter" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ text "Count: 0" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ text "Count: 1" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ text "Count: 3" ]
        |> PagesProgram.clickButton "-"
        |> PagesProgram.ensureViewHas [ text "Count: 2" ]
        |> PagesProgram.clickButton "Reset"
        |> PagesProgram.ensureViewHas [ text "Count: 0" ]


navigationTest : TestApp.ProgramTest
navigationTest =
    TestApp.start "/links" BackendTaskTest.init
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/links")
        |> PagesProgram.ensureViewHas [ text "Links Page" ]
        |> PagesProgram.clickLink "Go to Counter" "/counter"
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/counter")
        |> PagesProgram.ensureViewHas [ text "Count: 0" ]


navigateAndInteractTest : TestApp.ProgramTest
navigateAndInteractTest =
    TestApp.start "/links" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ text "Links Page" ]
        |> PagesProgram.clickLink "Go to Counter" "/counter"
        |> PagesProgram.ensureViewHas [ text "Count: 0" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ text "Count: 2" ]
        |> PagesProgram.clickButton "Reset"
        |> PagesProgram.ensureViewHas [ text "Count: 0" ]
        |> PagesProgram.navigateTo "/hello"
        |> PagesProgram.ensureViewHas [ text "Hello" ]


{-| Demonstrates the full framework data refresh lifecycle:
1. data reads "feedback.txt" and displays its content
2. User types a message and submits the form
3. action writes the message to "feedback.txt"
4. Framework automatically re-resolves data, which reads the updated file
5. The view shows both the action result AND the updated file content
-}
feedbackFormTest : TestApp.ProgramTest
feedbackFormTest =
    TestApp.start "/feedback"
        (BackendTaskTest.init
            |> BackendTaskTest.withFile "feedback.txt" "No messages yet"
        )
        |> PagesProgram.ensureViewHas [ text "Current file: No messages yet" ]
        |> PagesProgram.ensureViewHasNot [ text "You said:" ]
        |> PagesProgram.fillIn "feedback-form" "message" "Hello from tests!"
        |> PagesProgram.clickButton "Submit Feedback"
        -- After submission, action wrote "Hello from tests!" to feedback.txt.
        -- The framework re-resolved data, which reads the updated file.
        |> PagesProgram.ensureViewHas [ text "You said: Hello from tests!" ]
        |> PagesProgram.ensureViewHas [ text "Current file: Hello from tests!" ]
