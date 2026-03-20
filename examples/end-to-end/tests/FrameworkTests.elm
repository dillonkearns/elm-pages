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
import Pages.StaticHttp.Request
import RequestsAndPending
import Test.Html.Selector exposing (text)
import Test.PagesProgram as PagesProgram
import TestApp


counterClicksTest : TestApp.ProgramTest
counterClicksTest =
    TestApp.start "/counter" mockData
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
    TestApp.start "/links" mockData
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/links")
        |> PagesProgram.ensureViewHas [ text "Links Page" ]
        |> PagesProgram.clickLink "Go to Counter" "/counter"
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/counter")
        |> PagesProgram.ensureViewHas [ text "Count: 0" ]


navigateAndInteractTest : TestApp.ProgramTest
navigateAndInteractTest =
    TestApp.start "/links" mockData
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


feedbackFormTest : TestApp.ProgramTest
feedbackFormTest =
    TestApp.start "/feedback" mockData
        |> PagesProgram.ensureViewHas [ text "Feedback Form" ]
        |> PagesProgram.ensureViewHasNot [ text "You said:" ]
        |> PagesProgram.submitForm
            { formId = "feedback-form"
            , fields = [ ( "message", "Hello from tests!" ) ]
            }
        |> PagesProgram.ensureViewHas [ text "You said: Hello from tests!" ]


mockData : Pages.StaticHttp.Request.Request -> Maybe RequestsAndPending.Response
mockData request =
    Nothing
