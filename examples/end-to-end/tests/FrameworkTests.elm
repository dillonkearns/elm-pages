module FrameworkTests exposing
    ( counterClicksTest
    , navigationTest
    , navigateAndInteractTest
    , feedbackFormTest
    , loginRedirectTest
    , errorPageTest
    , concurrentSubmissionTest
    , loginSessionTest
    , greetWithQueryParamTest
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
        |> PagesProgram.ensureViewHas [ text "You said: Hello from tests!" ]
        |> PagesProgram.ensureViewHas [ text "Current file: Hello from tests!" ]


{-| Demonstrates action redirect: submit login form -> redirect to counter page.
The entire flow happens through the real Platform lifecycle.
-}
loginRedirectTest : TestApp.ProgramTest
loginRedirectTest =
    TestApp.start "/simple-login" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ text "Simple Login" ]
        |> PagesProgram.fillIn "login-form" "username" "alice"
        |> PagesProgram.clickButton "Log In"
        -- Action returned Route.redirectTo Route.Counter
        -- Framework follows the redirect automatically
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/counter")


{-| When a route's data BackendTask fails with FatalError, the framework
renders the error page instead of crashing.
-}
errorPageTest : TestApp.ProgramTest
errorPageTest =
    TestApp.start "/error-handling" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ text "Something's Not Right Here" ]


{-| Concurrent form submission with SubmitFetcher.
The form uses withConcurrent, so submission status is tracked
in concurrentSubmissions and the page doesn't block navigation.
-}
concurrentSubmissionTest : TestApp.ProgramTest
concurrentSubmissionTest =
    TestApp.start "/quick-note" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ text "Quick Note" ]
        |> PagesProgram.fillIn "note-form" "note" "My test note"
        |> PagesProgram.clickButton "Save Note"
        |> PagesProgram.ensureViewHas [ text "Saved: My test note" ]


{-| Full login session flow with cookie jar:
1. Start at /login -- no session yet, shows "You aren't logged in yet."
2. Fill in username, submit form
3. Action sets session cookie (encrypt simulation), redirects to /greet
4. /greet reads session cookie (decrypt simulation), shows greeting
5. Flash message appears ("Welcome <name>!")

This exercises the full cookie jar: action response Set-Cookie headers
are captured and included in subsequent data requests.

NOTE: Currently this test verifies the redirect works but the session
data flow is still being debugged (cookie jar captures cookies, but
the Greet route's session decrypt may not resolve in the virtual FS).
-}
loginSessionTest : TestApp.ProgramTest
loginSessionTest =
    TestApp.start "/login"
        (BackendTaskTest.init
            |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        )
        |> PagesProgram.ensureViewHas [ text "You aren't logged in yet." ]
        |> PagesProgram.fillIn "form" "name" "Alice"
        |> PagesProgram.clickButton "Log in"
        -- Action sets session cookie and redirects to /greet
        -- Note: Greet's data function uses MySession.expectSessionOrRedirect
        -- which, if session decryption fails, redirects back to /login.
        -- If we end up back at /login, verify the redirect at least happened.
        -- Action sets session cookie and redirects to /greet
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/greet")
        -- Greet route reads session cookie, decrypts it, shows greeting
        |> PagesProgram.ensureViewHas [ text "Hello Alice!" ]
        -- Flash message from login action
        |> PagesProgram.ensureViewHas [ text "Welcome Alice!" ]


{-| Test that the Greet route works with query param bypass (no session needed).
This verifies the route itself works, independent of session/cookie issues.
-}
greetWithQueryParamTest : TestApp.ProgramTest
greetWithQueryParamTest =
    TestApp.start "/greet?name=Bob" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ text "Hello Bob!" ]
