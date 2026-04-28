module FrameworkTests exposing (suite)

{-| Framework-driven route tests using the real elm-pages Platform.
These tests drive Pages.Internal.Platform directly, so shared layout,
navigation, form submission, and all framework behavior works identically
to production.

View in browser: elm-pages dev, then open /\_tests

-}

import Expect
import Json.Encode as Encode
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as PSelector
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.CookieJar as CookieJar
import Test.PagesProgram.Session as Session
import TestApp


suite : PagesProgram.Test
suite =
    PagesProgram.describe "Framework end-to-end"
        [ PagesProgram.test "counter clicks update the view"
            (TestApp.start "/counter" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
            , PagesProgram.clickButton "+"
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 3" ]
            , PagesProgram.clickButton "-"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
            , PagesProgram.clickButton "Reset"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
            ]
        , PagesProgram.test "navigation between routes"
            (TestApp.start "/links" BackendTaskTest.init)
            [ PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/links")
            , PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
            , PagesProgram.clickLink "Go to Counter"
            , PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/counter")
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
            ]
        , PagesProgram.test "navigate then interact"
            (TestApp.start "/links" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
            , PagesProgram.clickLink "Go to Counter"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
            , PagesProgram.clickButton "+"
            , PagesProgram.clickButton "+"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
            , PagesProgram.clickButton "Reset"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
            , PagesProgram.navigateTo "/hello"
            , PagesProgram.ensureViewHas [ PSelector.text "Hello" ]
            ]
        , PagesProgram.test "feedback form: data refresh after action writes file"
            (TestApp.start "/feedback"
                (BackendTaskTest.init
                    |> BackendTaskTest.withFile "feedback.txt" "No messages yet"
                )
            )
            [ PagesProgram.ensureViewHas [ PSelector.text "Current file: No messages yet" ]
            , PagesProgram.ensureViewHasNot [ PSelector.text "You said:" ]
            , PagesProgram.fillIn "feedback-form" "message" "Hello from tests!"
            , PagesProgram.clickButton "Submit Feedback"
            , PagesProgram.ensureViewHas [ PSelector.text "You said: Hello from tests!" ]
            , PagesProgram.ensureViewHas [ PSelector.text "Current file: Hello from tests!" ]
            ]
        , PagesProgram.test "login form action redirects to counter"
            (TestApp.start "/simple-login" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Simple Login" ]
            , PagesProgram.fillIn "login-form" "username" "alice"
            , PagesProgram.clickButton "Log In"
            , PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/counter")
            ]
        , PagesProgram.test "error page when data BackendTask fails"
            (TestApp.start "/error-handling" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Something's Not Right Here" ] ]
        , PagesProgram.test "concurrent submission shows the fetcher result"
            (TestApp.start "/quick-note" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Quick Note" ]
            , PagesProgram.fillIn "note-form" "note" "My test note"
            , PagesProgram.clickButton "Save Note"
            , PagesProgram.ensureViewHas [ PSelector.text "Done: My test note" ]
            ]
        , PagesProgram.test "login session: cookie set, redirect, decrypt"
            (TestApp.start "/login"
                (BackendTaskTest.init
                    |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
                )
            )
            [ PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
            , PagesProgram.fillIn "form" "name" "Alice"
            , PagesProgram.clickButton "Log in"
            , PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/greet")
            , PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
            , PagesProgram.ensureViewHas [ PSelector.text "Welcome Alice!" ]
            ]
        , PagesProgram.test "seeded session flash is consumed after the first request"
            (TestApp.start "/greet"
                (BackendTaskTest.init
                    |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
                    |> CookieJar.withCookies
                        (CookieJar.init
                            |> CookieJar.setSession
                                { name = "mysession"
                                , secret = "test-secret"
                                , session =
                                    Session.init
                                        |> Session.withValue "name" "Alice"
                                        |> Session.withFlash "message" "Welcome Alice!"
                                }
                        )
                )
            )
            [ PagesProgram.ensureViewHas [ PSelector.text "Welcome Alice!" ]
            , PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
            , PagesProgram.navigateTo "/login"
            , PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/login")
            , PagesProgram.ensureViewHas [ PSelector.text "No flash" ]
            , PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
            ]
        , PagesProgram.test "greet route works with query param bypass"
            (TestApp.start "/greet?name=Bob" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Hello Bob!" ] ]
        , PagesProgram.test "dark mode toggle updates session"
            (TestApp.start "/dark-mode" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Current mode: Light Mode" ]
            , PagesProgram.clickButton "To Dark Mode"
            , PagesProgram.ensureViewHas [ PSelector.text "Current mode: Dark Mode" ]
            ]
        , PagesProgram.test "logout flow clears session and redirects"
            (TestApp.start "/login"
                (BackendTaskTest.init
                    |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
                )
            )
            [ PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
            , PagesProgram.fillIn "form" "name" "Alice"
            , PagesProgram.clickButton "Log in"
            , PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/greet")
            , PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
            , PagesProgram.clickButton "Logout"
            , PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/login")
            , PagesProgram.ensureViewHas [ PSelector.text "You have been successfully logged out." ]
            ]
        , PagesProgram.test "navigate to /http-data and resolve the simulated GET"
            (TestApp.start "/links" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
            , PagesProgram.navigateTo "/http-data"
            , PagesProgram.simulateHttpGet "https://api.example.com/posts"
                (Encode.object [ ( "title", Encode.string "Hello from API" ) ])
            , PagesProgram.ensureViewHas [ PSelector.text "Post: Hello from API" ]
            ]
        , PagesProgram.test "navigate to /http-data twice with separate simulated responses"
            (TestApp.start "/links" BackendTaskTest.init)
            [ PagesProgram.navigateTo "/http-data"
            , PagesProgram.simulateHttpGet "https://api.example.com/posts"
                (Encode.object [ ( "title", Encode.string "First Load" ) ])
            , PagesProgram.ensureViewHas [ PSelector.text "Post: First Load" ]
            , PagesProgram.navigateTo "/links"
            , PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
            , PagesProgram.navigateTo "/http-data"
            , PagesProgram.simulateHttpGet "https://api.example.com/posts"
                (Encode.object [ ( "title", Encode.string "Second Load" ) ])
            , PagesProgram.ensureViewHas [ PSelector.text "Post: Second Load" ]
            ]
        , PagesProgram.test "login then navigate to /http-data"
            (TestApp.start "/login"
                (BackendTaskTest.init
                    |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
                )
            )
            [ PagesProgram.ensureViewHas [ PSelector.text "You aren't logged in yet." ]
            , PagesProgram.fillIn "form" "name" "Alice"
            , PagesProgram.clickButton "Log in"
            , PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/greet")
            , PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
            , PagesProgram.navigateTo "/http-data"
            , PagesProgram.simulateHttpGet "https://api.example.com/posts"
                (Encode.object [ ( "title", Encode.string "After Login" ) ])
            , PagesProgram.ensureViewHas [ PSelector.text "Post: After Login" ]
            ]
        , PagesProgram.test "GET form submission updates URL and page data"
            (TestApp.start "/get-form" BackendTaskTest.init)
            [ PagesProgram.ensureViewHas [ PSelector.text "Current page: 1" ]
            , PagesProgram.clickButton "Page 2"
            , PagesProgram.ensureBrowserUrl
                (\url -> url |> Expect.equal "https://localhost:1234/get-form?page=2")
            , PagesProgram.ensureViewHas [ PSelector.text "Current page: 2" ]
            ]
        , PagesProgram.test "fetcher background reload keeps assertions live"
            (TestApp.start "/fetcher-http" BackendTaskTest.init)
            [ PagesProgram.simulateHttpGet
                "https://api.example.com/count"
                (Encode.object [ ( "count", Encode.int 0 ) ])
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
            , PagesProgram.clickButton "Increment"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
            , PagesProgram.simulateHttpGet
                "https://api.example.com/increment"
                (Encode.object [])
            , PagesProgram.ensureHttpGet "https://api.example.com/count"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
            , PagesProgram.simulateHttpGet
                "https://api.example.com/count"
                (Encode.object [ ( "count", Encode.int 1 ) ])
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
            ]
        , PagesProgram.test "stale fetcher reloads are canceled by newer submissions"
            (TestApp.start "/fetcher-http" BackendTaskTest.init)
            [ PagesProgram.simulateHttpGet
                "https://api.example.com/count"
                (Encode.object [ ( "count", Encode.int 0 ) ])
            , PagesProgram.clickButton "Increment"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
            , PagesProgram.simulateHttpGet
                "https://api.example.com/increment"
                (Encode.object [])
            , PagesProgram.ensureHttpGet "https://api.example.com/count"
            , PagesProgram.clickButton "Increment"
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
            , PagesProgram.simulateHttpGet
                "https://api.example.com/increment"
                (Encode.object [])
            , PagesProgram.simulateHttpGet
                "https://api.example.com/count"
                (Encode.object [ ( "count", Encode.int 2 ) ])
            , PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
            ]
        ]
