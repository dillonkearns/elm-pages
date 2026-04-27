module ViewerStripPrefixesTest exposing (suite)

{-| The codegen `stripWrapperPrefixes` pipeline (emitted into
`elm-stuff/elm-pages/test-viewer/TestApp.elm`) strips the generated
constructor wrappers (`ModelLogin`, `DataLogin`, `ActionDataLogin`,
…) from `Debug.toString` output so the Model tab reads inner
records directly.

If the strip list is ordered shortest-first, `String.replace
"DataLogin "` greedily eats the `DataLogin` substring inside
`ActionDataLogin`, leaving an orphan `Action` glued to the record
that follows it (`Action{...}` with no space). That output then
fails to parse in `DebugParser.parse`.

This module pins the ordering invariant so a regression doesn't
sneak back in.

-}

import Expect
import Test exposing (Test, describe, test)
import Test.PagesProgram.DebugParser as DP


{-| Mirrors the strip pipeline the codegen generates for a project
with `Login` and `Visibility__` route templates. The list is sorted
longest-first so longer prefixes win.
-}
stripWrapperPrefixes : String -> String
stripWrapperPrefixes s =
    s
        |> String.replace "ActionDataVisibility__ " ""
        |> String.replace "ActionDataLogin " ""
        |> String.replace "ModelVisibility__ " ""
        |> String.replace "ModelErrorPage____ " ""
        |> String.replace "DataVisibility__ " ""
        |> String.replace "DataErrorPage____ " ""
        |> String.replace "ModelLogin " ""
        |> String.replace "DataLogin " ""
        |> String.replace "NotFound" "(not-found)"
        |> String.replace "Data404NotFoundPage____" "(404)"


{-| The buggy ordering: `DataLogin` shows up before `ActionDataLogin`,
so the inner `DataLogin` substring of `ActionDataLogin` gets eaten
first.
-}
stripWrapperPrefixesBuggy : String -> String
stripWrapperPrefixesBuggy s =
    s
        |> String.replace "ModelLogin " ""
        |> String.replace "DataLogin " ""
        |> String.replace "ActionDataLogin " ""
        |> String.replace "ModelVisibility__ " ""
        |> String.replace "DataVisibility__ " ""
        |> String.replace "ActionDataVisibility__ " ""


suite : Test
suite =
    describe "stripWrapperPrefixes"
        [ test "leaves a space between the unwrapped value and what follows" <|
            \() ->
                stripWrapperPrefixes
                    "Just (ActionDataLogin { maybeError = Nothing, sentLink = True })"
                    |> Expect.equal
                        "Just ({ maybeError = Nothing, sentLink = True })"
        , test "buggy shortest-first ordering produces unparseable output" <|
            \() ->
                let
                    output : String
                    output =
                        stripWrapperPrefixesBuggy
                            "Just (ActionDataLogin { maybeError = Nothing, sentLink = True })"
                in
                output
                    |> Expect.equal
                        "Just (Action{ maybeError = Nothing, sentLink = True })"
        , test "DebugParser fails on the buggy output" <|
            \() ->
                let
                    output : String
                    output =
                        stripWrapperPrefixesBuggy
                            "Just (ActionDataLogin { maybeError = Nothing, sentLink = True })"
                in
                case DP.parse output of
                    Ok _ ->
                        Expect.fail
                            ("Expected parse to fail on the buggy output but it succeeded: "
                                ++ output
                            )

                    Err _ ->
                        Expect.pass
        , test "DebugParser succeeds on the correctly-stripped output" <|
            \() ->
                let
                    output : String
                    output =
                        stripWrapperPrefixes
                            "Just (ActionDataLogin { maybeError = Nothing, sentLink = True })"
                in
                case DP.parse output of
                    Ok _ ->
                        Expect.pass

                    Err _ ->
                        Expect.fail ("Expected parse success but got Err on: " ++ output)
        , test "real failing snapshot from the test viewer parses end-to-end" <|
            \() ->
                let
                    -- The buggy output the user reported (verbatim).
                    buggyInput : String
                    buggyInput =
                        "{ app = { action = Just (Action{ maybeError = Nothing, sentLink = True }), concurrentSubmissions = Dict.fromList [], data = { username = Nothing }, navigation = Just (0,Loading [\"login\"] Load), pageFormState = Dict.fromList [(\"login\",{ fields = Dict.fromList [(\"email\",{ status = Changed, value = \"user@example.com\" })], submitAttempted = True })], sharedData = () }, model = {}, shared = { showMobileMenu = False } }"

                    -- What stripWrapperPrefixes would have emitted with
                    -- the correct longest-first ordering.
                    correctlyStripped : String
                    correctlyStripped =
                        "{ app = { action = Just ({ maybeError = Nothing, sentLink = True }), concurrentSubmissions = Dict.fromList [], data = { username = Nothing }, navigation = Just (0,Loading [\"login\"] Load), pageFormState = Dict.fromList [(\"login\",{ fields = Dict.fromList [(\"email\",{ status = Changed, value = \"user@example.com\" })], submitAttempted = True })], sharedData = () }, model = {}, shared = { showMobileMenu = False } }"
                in
                Expect.all
                    [ \_ ->
                        case DP.parse buggyInput of
                            Ok _ ->
                                Expect.fail "Buggy snapshot should not parse"

                            Err _ ->
                                Expect.pass
                    , \_ ->
                        case DP.parse correctlyStripped of
                            Ok _ ->
                                Expect.pass

                            Err _ ->
                                Expect.fail ("Correctly-stripped snapshot should parse but did not: " ++ correctlyStripped)
                    ]
                    ()
        ]
