module DocsModelInspectorTest exposing (suite)

{-| TDD: the modelState surfaced by the visual test runner should
contain only the user-facing app shape (`{ app, model, shared }`),
not test-harness internals (`cookieJar`, `virtualFs`, `platformModel`).

Runs `DocsTests.landingPageTest` exactly as the visual test viewer
would, then asserts that the captured model snapshot does not leak
harness state. `TestApp.start` already auto-wires a `viewerStateString`
extractor that produces the right shape — this test fails when a test
case clobbers it by chaining `|> withModelInspector Debug.toString`
afterwards.

-}

import DocsTests
import Expect
import Test exposing (..)


suite : Test
suite =
    describe "DocsTests model inspector"
        [ test "landingPageTest modelState does not leak harness internals" <|
            \() ->
                DocsTests.landingPageSnapshots
                    |> List.filterMap .modelState
                    |> List.head
                    |> Maybe.withDefault "<no model snapshot>"
                    |> Expect.all
                        [ refute "cookieJar"
                        , refute "virtualFs"
                        , refute "platformModel"
                        ]
        ]


refute : String -> String -> Expect.Expectation
refute needle haystack =
    if String.contains needle haystack then
        Expect.fail
            ("Expected modelState to NOT contain '"
                ++ needle
                ++ "', but it did. Full snapshot:\n\n"
                ++ haystack
            )

    else
        Expect.pass
