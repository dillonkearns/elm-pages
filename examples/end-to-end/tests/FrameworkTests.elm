module FrameworkTests exposing
    ( counterClicksTest
    , navigationTest
    , navigateAndInteractTest
    , feedbackFormTest
    , loginRedirectTest
    , errorPageTest
    , concurrentSubmissionTest
    , loginSessionTest
    , seededSessionFlashTest
    , greetWithQueryParamTest
    , darkModeToggleTest
    , logoutFlowTest
    , httpDataNavigationTest
    , httpDataDoubleNavigationTest
    , httpDataAfterLoginTest
    , getFormSubmissionTest
    , fetcherBackgroundReloadTest
    , fetcherStaleReloadCancellationTest
    )

{-| Framework-driven route tests using the real elm-pages Platform.
These tests drive Pages.Internal.Platform directly, so shared layout,
navigation, form submission, and all framework behavior works identically
to production.

View in browser: elm-pages test-view tests/FrameworkTests.elm
-}

import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.Selector as PSelector
import TestApp


counterClicksTest : TestApp.ProgramTest
counterClicksTest =
    TestApp.start "/counter" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 3" ]
        |> PagesProgram.clickButton "-"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
        |> PagesProgram.clickButton "Reset"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]


navigationTest : TestApp.ProgramTest
navigationTest =
    TestApp.start "/links" BackendTaskTest.init
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/links")
        |> PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
        |> PagesProgram.clickLink "Go to Counter"
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/counter")
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]


navigateAndInteractTest : TestApp.ProgramTest
navigateAndInteractTest =
    TestApp.start "/links" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
        |> PagesProgram.clickLink "Go to Counter"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
        |> PagesProgram.clickButton "+"
        |> PagesProgram.clickButton "+"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
        |> PagesProgram.clickButton "Reset"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
        |> PagesProgram.navigateTo "/hello"
        |> PagesProgram.ensureViewHas [ PSelector.text "Hello" ]


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
        |> PagesProgram.ensureViewHas [ PSelector.text "Current file: No messages yet" ]
        |> PagesProgram.ensureViewHasNot [ PSelector.text "You said:" ]
        |> PagesProgram.fillIn "feedback-form" "message" "Hello from tests!"
        |> PagesProgram.clickButton "Submit Feedback"
        |> PagesProgram.ensureViewHas [ PSelector.text "You said: Hello from tests!" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Current file: Hello from tests!" ]


{-| Demonstrates action redirect: submit login form -> redirect to counter page.
The entire flow happens through the real Platform lifecycle.
-}
loginRedirectTest : TestApp.ProgramTest
loginRedirectTest =
    TestApp.start "/simple-login" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ PSelector.text "Simple Login" ]
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
        |> PagesProgram.ensureViewHas [ PSelector.text "Something's Not Right Here" ]


{-| Concurrent form submission with SubmitFetcher.
The form uses withConcurrent, so submission status is tracked
in concurrentSubmissions and the page doesn't block navigation.
-}
concurrentSubmissionTest : TestApp.ProgramTest
concurrentSubmissionTest =
    TestApp.start "/quick-note" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ PSelector.text "Quick Note" ]
        |> PagesProgram.fillIn "note-form" "note" "My test note"
        |> PagesProgram.clickButton "Save Note"
        |> PagesProgram.ensureViewHas [ PSelector.text "Done: My test note" ]


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
        |> PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
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
        |> PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
        -- Flash message from login action
        |> PagesProgram.ensureViewHas [ PSelector.text "Welcome Alice!" ]


{-| Start with a seeded session and flash value, then verify the flash is
consumed after the first request while the persistent session data remains.
-}
seededSessionFlashTest : TestApp.ProgramTest
seededSessionFlashTest =
    TestApp.start "/greet"
        (BackendTaskTest.init
            |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
            |> BackendTaskTest.withSessionCookie
                { name = "mysession"
                , session =
                    BackendTaskTest.session
                        |> BackendTaskTest.withSessionValue "name" "Alice"
                        |> BackendTaskTest.withFlashValue "message" "Welcome Alice!"
                }
        )
        |> PagesProgram.ensureViewHas [ PSelector.text "Welcome Alice!" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
        |> PagesProgram.navigateTo "/login"
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/login")
        |> PagesProgram.ensureViewHas [ PSelector.text "No flash" ]
        |> PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]


{-| Test that the Greet route works with query param bypass (no session needed).
This verifies the route itself works, independent of session/cookie issues.
-}
greetWithQueryParamTest : TestApp.ProgramTest
greetWithQueryParamTest =
    TestApp.start "/greet?name=Bob" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ PSelector.text "Hello Bob!" ]


{-| DarkMode uses sessions with hardcoded secret "test" to persist
dark/light mode preference. Tests the full cookie toggle cycle:
1. Start in light mode (no session)
2. Click "To Dark Mode" button (form with hidden checkbox field)
3. Action sets session cookie with darkMode=dark
4. Data re-resolves, reads session, shows dark mode
-}
darkModeToggleTest : TestApp.ProgramTest
darkModeToggleTest =
    TestApp.start "/dark-mode" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ PSelector.text "Current mode: Light Mode" ]
        |> PagesProgram.clickButton "To Dark Mode"
        |> PagesProgram.ensureViewHas [ PSelector.text "Current mode: Dark Mode" ]


{-| Full login -> logout -> login flow:
1. Login as Alice -> redirects to /greet with session
2. Verify "Hello Alice!" (session persists)
3. Navigate to /logout and submit form
4. Logout clears session, redirects to /login with flash
5. Verify flash message "You have been successfully logged out."
-}
logoutFlowTest : TestApp.ProgramTest
logoutFlowTest =
    TestApp.start "/login"
        (BackendTaskTest.init
            |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        )
        |> PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
        |> PagesProgram.fillIn "form" "name" "Alice"
        |> PagesProgram.clickButton "Log in"
        -- Logged in, redirected to /greet
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/greet")
        |> PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
        |> PagesProgram.clickButton "Logout"
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/login")
        |> PagesProgram.ensureViewHas [ PSelector.text "You have been successfully logged out." ]


{-| Test navigating to a route whose data BackendTask does an HTTP request.
The test navigates to /http-data and provides the HTTP response via
simulateHttpGet. This exercises the pause-and-resume architecture.
-}
httpDataNavigationTest : TestApp.ProgramTest
httpDataNavigationTest =
    TestApp.start "/links" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
        |> PagesProgram.navigateTo "/http-data"
        -- Navigation triggers data resolution which hits HTTP GET to api.example.com.
        -- The framework pauses. Provide the simulated response:
        |> PagesProgram.simulateHttpGet "https://api.example.com/posts"
            (Encode.object [ ( "title", Encode.string "Hello from API" ) ])
        -- Data resolved, page renders
        |> PagesProgram.ensureViewHas [ PSelector.text "Post: Hello from API" ]


{-| Navigate to HTTP-data route twice: tests that after the first data resume
completes, the second navigation also correctly pauses and resumes.
-}
httpDataDoubleNavigationTest : TestApp.ProgramTest
httpDataDoubleNavigationTest =
    TestApp.start "/links" BackendTaskTest.init
        |> PagesProgram.navigateTo "/http-data"
        |> PagesProgram.simulateHttpGet "https://api.example.com/posts"
            (Encode.object [ ( "title", Encode.string "First Load" ) ])
        |> PagesProgram.ensureViewHas [ PSelector.text "Post: First Load" ]
        -- Navigate back, then to http-data again
        |> PagesProgram.navigateTo "/links"
        |> PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
        |> PagesProgram.navigateTo "/http-data"
        |> PagesProgram.simulateHttpGet "https://api.example.com/posts"
            (Encode.object [ ( "title", Encode.string "Second Load" ) ])
        |> PagesProgram.ensureViewHas [ PSelector.text "Post: Second Load" ]


{-| Login via session action (no HTTP), redirect to /greet, then navigate
to /http-data which requires HTTP for data. This mirrors the smoothie pattern
where login redirects to an index page that needs HTTP data.
-}
httpDataAfterLoginTest : TestApp.ProgramTest
httpDataAfterLoginTest =
    TestApp.start "/login"
        (BackendTaskTest.init
            |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
        )
        |> PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
        |> PagesProgram.fillIn "form" "name" "Alice"
        |> PagesProgram.clickButton "Log in"
        -- Redirect to /greet after login
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/greet")
        |> PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
        -- Now navigate to /http-data which needs HTTP
        |> PagesProgram.navigateTo "/http-data"
        |> PagesProgram.simulateHttpGet "https://api.example.com/posts"
            (Encode.object [ ( "title", Encode.string "After Login" ) ])
        |> PagesProgram.ensureViewHas [ PSelector.text "Post: After Login" ]


{-| GET forms should use browser-style query-param submissions and update the URL.
-}
getFormSubmissionTest : TestApp.ProgramTest
getFormSubmissionTest =
    TestApp.start "/get-form" BackendTaskTest.init
        |> PagesProgram.ensureViewHas [ PSelector.text "Current page: 1" ]
        |> PagesProgram.clickButton "Page 2"
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/get-form?page=2")
        |> PagesProgram.ensureViewHas [ PSelector.text "Current page: 2" ]


{-| Fetcher-driven background reloads should leave the view/assertion API live
while the reload request is still pending.
-}
fetcherBackgroundReloadTest : TestApp.ProgramTest
fetcherBackgroundReloadTest =
    TestApp.start "/fetcher-http" BackendTaskTest.init
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/count"
            (Encode.object [ ( "count", Encode.int 0 ) ])
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
        |> PagesProgram.clickButton "Increment"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
        |> PagesProgram.simulateHttpGetTo
            "https://api.example.com/increment"
            (Encode.object [])
        |> PagesProgram.ensurePendingHttpGet "https://api.example.com/count"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
        |> PagesProgram.simulateHttpGetTo
            "https://api.example.com/count"
            (Encode.object [ ( "count", Encode.int 1 ) ])
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]


{-| When a second fetcher submission supersedes a stale reload, the stale response
should be canceled so a single final reload response settles the page.
-}
fetcherStaleReloadCancellationTest : TestApp.ProgramTest
fetcherStaleReloadCancellationTest =
    TestApp.start "/fetcher-http" BackendTaskTest.init
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/count"
            (Encode.object [ ( "count", Encode.int 0 ) ])
        |> PagesProgram.clickButton "Increment"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/increment"
            (Encode.object [])
        |> PagesProgram.ensurePendingHttpGet "https://api.example.com/count"
        |> PagesProgram.clickButton "Increment"
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/increment"
            (Encode.object [])
        |> PagesProgram.ensurePendingHttpGetCount "https://api.example.com/count" 1
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/count"
            (Encode.object [ ( "count", Encode.int 2 ) ])
        |> PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
