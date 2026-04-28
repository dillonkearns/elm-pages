module PlatformTests exposing (suite)

import Expect exposing (Expectation)
import Html.Attributes as Attr
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as PSelector
import Test.PagesProgram as PagesProgram
import Test.Runner
import TestApp


suite : Test
suite =
    describe "Platform-based tests (real framework)"
        [ test "counter page renders through Shared layout" <|
            \() ->
                PagesProgram.expect (TestApp.start "/counter" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ] ]
        , test "hello page renders" <|
            \() ->
                PagesProgram.expect (TestApp.start "/hello" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Hello" ] ]
        , test "counter increment and decrement" <|
            \() ->
                PagesProgram.expect (TestApp.start "/counter" BackendTaskTest.init)
                    [ PagesProgram.clickButton "+"
                    , PagesProgram.clickButton "+"
                    , PagesProgram.clickButton "+"
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 3" ]
                    , PagesProgram.clickButton "-"
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
                    ]
        , test "navigate from links to counter" <|
            \() ->
                PagesProgram.expect (TestApp.start "/links" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
                    , PagesProgram.clickLink "Go to Counter"
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    ]
        , test "navigate and then interact" <|
            \() ->
                PagesProgram.expect (TestApp.start "/links" BackendTaskTest.init)
                    [ PagesProgram.clickLink "Go to Counter"
                    , PagesProgram.clickButton "+"
                    , PagesProgram.clickButton "+"
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
                    ]
        , test "ensureBrowserUrl tracks navigation" <|
            \() ->
                PagesProgram.expect (TestApp.start "/links" BackendTaskTest.init)
                    [ PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/links")
                    , PagesProgram.navigateTo "/counter"
                    , PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/counter")
                    ]
        , test "form submit with file read/write data refresh" <|
            \() ->
                PagesProgram.expect
                    (TestApp.start "/feedback"
                        (BackendTaskTest.init
                            |> BackendTaskTest.withFile "feedback.txt" "No messages yet"
                        )
                    )
                    [ PagesProgram.ensureViewHas [ PSelector.text "Current file: No messages yet" ]
                    , PagesProgram.fillIn "feedback-form" "message" "Hello!"
                    , PagesProgram.clickButton "Submit Feedback"
                    , PagesProgram.ensureViewHas [ PSelector.text "You said: Hello!" ]
                    , PagesProgram.ensureViewHas [ PSelector.text "Current file: Hello!" ]
                    ]
        , test "error page renders when data BackendTask fails" <|
            \() ->
                PagesProgram.expect (TestApp.start "/error-handling" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Something's Not Right Here" ] ]
        , test "concurrent form submission with fetcher" <|
            \() ->
                PagesProgram.expect (TestApp.start "/quick-note" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Quick Note" ]
                    , PagesProgram.fillIn "note-form" "note" "My test note"
                    , PagesProgram.clickButton "Save Note"
                    , PagesProgram.ensureViewHas [ PSelector.text "Done: My test note" ]
                    ]
        , test "login form redirects to counter" <|
            \() ->
                PagesProgram.expect (TestApp.start "/simple-login" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Simple Login" ]
                    , PagesProgram.fillIn "login-form" "username" "alice"
                    , PagesProgram.clickButton "Log In"
                    , PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/counter")
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    ]
        , test "fillIn value is reflected in the rendered view" <|
            \() ->
                PagesProgram.expect
                    (TestApp.start "/feedback"
                        (BackendTaskTest.init
                            |> BackendTaskTest.withFile "feedback.txt" "No messages yet"
                        )
                    )
                    [ PagesProgram.ensureViewHas [ PSelector.text "Current file: No messages yet" ]
                    , PagesProgram.fillIn "feedback-form" "message" "Hello from test!"
                    , PagesProgram.ensureViewHas
                        [ PSelector.tag "input"
                        , PSelector.attribute (Attr.name "message")
                        , PSelector.attribute (Attr.value "Hello from test!")
                        ]
                    ]
        , test "navigating to route with unsimulated HTTP in data surfaces pending request error" <|
            \() ->
                PagesProgram.expect (TestApp.start "/counter" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    , PagesProgram.navigateTo "/http-data"
                    , PagesProgram.ensureViewHas [ PSelector.text "Post:" ]
                    ]
                    |> expectFailContaining
                        "Route data has a pending BackendTask that needs a simulated response"
        , test "pending HTTP error message includes the request URL" <|
            \() ->
                PagesProgram.expect (TestApp.start "/counter" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    , PagesProgram.navigateTo "/http-data"
                    , PagesProgram.ensureViewHas [ PSelector.text "Post:" ]
                    ]
                    |> expectFailContaining "https://api.example.com/posts"
        , test "fetcher-http route: initial data load needs HTTP" <|
            \() ->
                PagesProgram.expect (TestApp.start "/fetcher-http" BackendTaskTest.init)
                    [ PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    ]
        , test "fetcher-http: URL-targeted simulation" <|
            \() ->
                PagesProgram.expect (TestApp.start "/fetcher-http" BackendTaskTest.init)
                    [ PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    , PagesProgram.clickButton "Increment"
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                    , PagesProgram.simulateHttpGet
                        "https://api.example.com/increment"
                        (Encode.object [])
                    , PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 1 ) ])
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                    ]
        , test "fetcher-http: single increment with optimistic UI" <|
            \() ->
                PagesProgram.expect (TestApp.start "/fetcher-http" BackendTaskTest.init)
                    [ PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    , PagesProgram.clickButton "Increment"
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                    , PagesProgram.simulateHttpGet
                        "https://api.example.com/increment"
                        (Encode.object [])
                    , PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 1 ) ])
                    , PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                    ]
        , test "done fails while a fetcher HTTP request is still pending" <|
            \() ->
                PagesProgram.expect (TestApp.start "/fetcher-http" BackendTaskTest.init)
                    [ PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
                    , PagesProgram.clickButton "Increment"
                    ]
                    |> expectFailContaining "https://api.example.com/increment"
        , test "GET form submission updates the URL and page data" <|
            \() ->
                PagesProgram.expect (TestApp.start "/get-form" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Current page: 1" ]
                    , PagesProgram.clickButton "Page 2"
                    , PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/get-form?page=2")
                    , PagesProgram.ensureViewHas [ PSelector.text "Current page: 2" ]
                    ]
        , test "GET form submission appends fields to existing query parameters" <|
            \() ->
                PagesProgram.expect (TestApp.start "/get-form?sort=recent" BackendTaskTest.init)
                    [ PagesProgram.ensureViewHas [ PSelector.text "Current page: 1" ]
                    , PagesProgram.clickButton "Page 2"
                    , PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/get-form?sort=recent&page=2")
                    , PagesProgram.ensureViewHas [ PSelector.text "Current page: 2" ]
                    ]
        , test "raw cross-route logout form clears the session and redirects" <|
            \() ->
                PagesProgram.expect
                    (TestApp.start "/login"
                        (BackendTaskTest.init
                            |> BackendTaskTest.withEnv "SESSION_SECRET" "test-secret"
                        )
                    )
                    [ PagesProgram.fillIn "form" "name" "Alice"
                    , PagesProgram.clickButton "Log in"
                    , PagesProgram.ensureViewHas [ PSelector.text "Hello Alice!" ]
                    , PagesProgram.clickButton "Logout"
                    , PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/login")
                    , PagesProgram.ensureViewHas [ PSelector.text "You have been successfully logged out." ]
                    ]
        , test "fetcher background reload keeps view assertions live" <|
            \() ->
                PagesProgram.expect (TestApp.start "/fetcher-http" BackendTaskTest.init)
                    [ PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
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
        , test "stale fetcher reloads are canceled when a newer submission starts" <|
            \() ->
                PagesProgram.expect (TestApp.start "/fetcher-http" BackendTaskTest.init)
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


expectFailContaining : String -> Expectation -> Expectation
expectFailContaining substring expectation =
    case Test.Runner.getFailureReason expectation of
        Nothing ->
            Expect.fail
                ("Expected test to fail with message containing \""
                    ++ substring
                    ++ "\", but it passed."
                )

        Just { description } ->
            if String.contains substring description then
                Expect.pass

            else
                Expect.fail
                    ("Expected failure message to contain \""
                        ++ substring
                        ++ "\", but the actual message was:\n\n"
                        ++ description
                    )
