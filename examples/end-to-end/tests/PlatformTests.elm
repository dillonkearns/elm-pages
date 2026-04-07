module PlatformTests exposing (suite)

import Expect exposing (Expectation)
import Html.Attributes as Attr
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import Test.PagesProgram.Selector as PSelector
import Test.Runner
import TestApp


suite : Test
suite =
    describe "Platform-based tests (real framework)"
        [ test "counter page renders through Shared layout" <|
            \() ->
                TestApp.start "/counter" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    |> PagesProgram.done
        , test "hello page renders" <|
            \() ->
                TestApp.start "/hello" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ PSelector.text "Hello" ]
                    |> PagesProgram.done
        , test "counter increment and decrement" <|
            \() ->
                TestApp.start "/counter" BackendTaskTest.init
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 3" ]
                    |> PagesProgram.clickButton "-"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
                    |> PagesProgram.done
        , test "navigate from links to counter" <|
            \() ->
                TestApp.start "/links" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ PSelector.text "Links Page" ]
                    |> PagesProgram.clickLink "Go to Counter"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    |> PagesProgram.done
        , test "navigate and then interact" <|
            \() ->
                TestApp.start "/links" BackendTaskTest.init
                    |> PagesProgram.clickLink "Go to Counter"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.clickButton "+"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 2" ]
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
                    |> PagesProgram.ensureViewHas [ PSelector.text "Current file: No messages yet" ]
                    |> PagesProgram.fillIn "feedback-form" "message" "Hello!"
                    |> PagesProgram.clickButton "Submit Feedback"
                    -- Action wrote "Hello!" to feedback.txt.
                    -- Framework re-resolved data, which reads the updated file.
                    |> PagesProgram.ensureViewHas [ PSelector.text "You said: Hello!" ]
                    |> PagesProgram.ensureViewHas [ PSelector.text "Current file: Hello!" ]
                    |> PagesProgram.done
        , test "error page renders when data BackendTask fails" <|
            \() ->
                TestApp.start "/error-handling" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ PSelector.text "Something's Not Right Here" ]
                    |> PagesProgram.done
        , test "concurrent form submission with fetcher" <|
            \() ->
                TestApp.start "/quick-note" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ PSelector.text "Quick Note" ]
                    |> PagesProgram.fillIn "note-form" "note" "My test note"
                    |> PagesProgram.clickButton "Save Note"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Done: My test note" ]
                    |> PagesProgram.done
        , test "login form redirects to counter" <|
            \() ->
                TestApp.start "/simple-login" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ PSelector.text "Simple Login" ]
                    |> PagesProgram.fillIn "login-form" "username" "alice"
                    |> PagesProgram.clickButton "Log In"
                    |> PagesProgram.ensureBrowserUrl
                        (\url -> url |> Expect.equal "https://localhost:1234/counter")
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    |> PagesProgram.done
        , test "fillIn value is reflected in the rendered view" <|
            \() ->
                TestApp.start "/feedback"
                    (BackendTaskTest.init
                        |> BackendTaskTest.withFile "feedback.txt" "No messages yet"
                    )
                    |> PagesProgram.ensureViewHas [ PSelector.text "Current file: No messages yet" ]
                    |> PagesProgram.fillIn "feedback-form" "message" "Hello from test!"
                    |> PagesProgram.ensureViewHas
                        [ PSelector.tag "input"
                        , PSelector.attribute "name=\"message\"" (Selector.attribute (Attr.name "message"))
                        , PSelector.value "Hello from test!"
                        ]
                    |> PagesProgram.done
        , test "navigating to route with unsimulated HTTP in data surfaces pending request error" <|
            \() ->
                TestApp.start "/counter" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    |> PagesProgram.navigateTo "/http-data"
                    -- /http-data's data function does GET https://api.example.com/posts
                    -- which has not been simulated. ensureViewHas should report the
                    -- pending HTTP request, not a misleading "not found" view error.
                    |> PagesProgram.ensureViewHas [ PSelector.text "Post:" ]
                    |> PagesProgram.done
                    |> expectFailContaining
                        "Route data has a pending BackendTask that needs a simulated response"
        , test "pending HTTP error message includes the request URL" <|
            \() ->
                TestApp.start "/counter" BackendTaskTest.init
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    |> PagesProgram.navigateTo "/http-data"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Post:" ]
                    |> PagesProgram.done
                    |> expectFailContaining "https://api.example.com/posts"
        , test "fetcher-http route: initial data load needs HTTP" <|
            \() ->
                -- Initial data needs HTTP GET simulation before page renders
                TestApp.start "/fetcher-http"
                    BackendTaskTest.init
                    |> PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    |> PagesProgram.done
        , test "fetcher-http: URL-targeted simulation" <|
            \() ->
                -- Use simulateHttpGetTo to target specific URLs regardless of order
                TestApp.start "/fetcher-http"
                    BackendTaskTest.init
                    |> PagesProgram.simulateHttpGetTo
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    |> PagesProgram.clickButton "Increment"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                    -- Resolve by URL (not order): target mutation directly
                    |> PagesProgram.simulateHttpGetTo
                        "https://api.example.com/increment"
                        (Encode.object [])
                    -- Data reload settles on the server count after the fetcher finishes.
                    |> PagesProgram.simulateHttpGetTo
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 1 ) ])
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                    |> PagesProgram.done
        , test "fetcher-http: single increment with optimistic UI" <|
            \() ->
                TestApp.start "/fetcher-http"
                    BackendTaskTest.init
                    |> PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 0" ]
                    -- Click shows optimistic +1 (fetcher pending)
                    |> PagesProgram.clickButton "Increment"
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                    -- Resolve fetcher mutation
                    |> PagesProgram.simulateHttpGet
                        "https://api.example.com/increment"
                        (Encode.object [])
                    -- Data reload completes, so the final view reflects the server count.
                    |> PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 1 ) ])
                    |> PagesProgram.ensureViewHas [ PSelector.text "Count: 1" ]
                    |> PagesProgram.done
        , test "done fails while a fetcher HTTP request is still pending" <|
            \() ->
                TestApp.start "/fetcher-http"
                    BackendTaskTest.init
                    |> PagesProgram.simulateHttpGet
                        "https://api.example.com/count"
                        (Encode.object [ ( "count", Encode.int 0 ) ])
                    |> PagesProgram.clickButton "Increment"
                    |> PagesProgram.done
                    |> expectFailContaining "https://api.example.com/increment"
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
