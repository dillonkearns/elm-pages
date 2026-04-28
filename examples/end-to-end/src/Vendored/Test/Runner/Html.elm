module Vendored.Test.Runner.Html exposing
    ( Config
    , viewResults
    , defaultConfig, withFuzzCount, showPassedTests, hidePassedTests
    )

{-| Vendored from jgrenat/elm-html-test-runner 1.0.3.

Original repo: <https://github.com/jgrenat/elm-html-test-runner>. Upstream
package depends on `elm-explorations/test` 1.x; vendoring here avoids the
dependency conflict with 2.x in this project.


# Definition

@docs Config


# Display tests results

@docs viewResults


# Configuration

@docs defaultConfig, withFuzzCount, showPassedTests, hidePassedTests

-}

import Array exposing (Array)
import Expect exposing (Expectation)
import Html exposing (Html, div, h3, li, p, pre, text, ul)
import Html.Attributes exposing (class, style)
import Random exposing (Seed)
import Test exposing (Test)
import Test.Runner exposing (Runner, fromTest, getFailureReason)
import Test.Runner.Failure exposing (InvalidReason(..), Reason(..))


{-| Config object used to define options like the fuzz count, the initial seed, whether or not the passed tests should be displayed...
-}
type Config
    = Config { initialSeed : Seed, fuzzCount : Int, passedTestsDisplay : PassedTestsDisplay }


type PassedTestsDisplay
    = Show
    | Hide


{-| Create a default config, initializing it with an initial seed used for fuzz testing.

    Random.initialSeed 10000 |> defaultConfig

-}
defaultConfig : Seed -> Config
defaultConfig initialSeed =
    Config
        { initialSeed = initialSeed
        , fuzzCount = 100
        , passedTestsDisplay = Show
        }


{-| Set the fuzz count in the Config. Should not be useful if you don't use fuzz testing.

    Random.initialSeed 10000 |> defaultConfig |> withFuzzCount 50

-}
withFuzzCount : Int -> Config -> Config
withFuzzCount runsCount (Config config) =
    Config { config | fuzzCount = runsCount }


{-| Indicates that the resulting HTML should show passed tests. This is the default behavior.

    Random.initialSeed 10000 |> defaultConfig |> showPassedTests

-}
showPassedTests : Config -> Config
showPassedTests (Config config) =
    Config { config | passedTestsDisplay = Show }


{-| Indicates that the resulting HTML should _NOT_ show passed tests.

    Random.initialSeed 10000 |> defaultConfig |> hidePassedTests

-}
hidePassedTests : Config -> Config
hidePassedTests (Config config) =
    Config { config | passedTestsDisplay = Hide }


{-| Run and display test results

    viewResults myConfig myTests

-}
viewResults : Config -> Test -> Html a
viewResults (Config config) testsToRun =
    case fromTest config.fuzzCount config.initialSeed testsToRun of
        Test.Runner.Plain tests ->
            div [] <| List.map (viewTestsResults config.passedTestsDisplay) tests

        Test.Runner.Only tests ->
            div [] <| List.map (viewTestsResults config.passedTestsDisplay) tests

        Test.Runner.Skipping tests ->
            div [] <| List.map (viewTestsResults config.passedTestsDisplay) tests

        Test.Runner.Invalid reason ->
            div []
                [ p [] [ text "Invalid tests, here is the reason:" ]
                , pre [] [ text reason ]
                ]


viewTestsResults : PassedTestsDisplay -> Runner -> Html a
viewTestsResults passedTestsDisplay runner =
    let
        label =
            List.intersperse " " runner.labels
                |> List.foldl (++) ""

        getExpectationResults =
            case passedTestsDisplay of
                Show ->
                    List.map viewExpectationResult
                        >> List.map (Maybe.withDefault (text "Passed!"))

                Hide ->
                    List.filterMap viewExpectationResult
    in
    runner.run ()
        |> getExpectationResults
        |> (\expectationsResults ->
                if List.length expectationsResults == 0 then
                    div [ class "test-pass" ]
                        [ h3 [] [ text label ]
                        , text "\u{2714}\u{FE0F} All tests passed"
                        ]

                else
                    let
                        isFailure result =
                            result /= text "Passed!"
                    in
                    List.map
                        (\result ->
                            div
                                [ class
                                    (if isFailure result then
                                        "test-fail"

                                     else
                                        "test-pass"
                                    )
                                ]
                                [ h3 [] [ text label ]
                                , result
                                ]
                        )
                        expectationsResults
                        |> div []
           )


viewExpectationResult : Expectation -> Maybe (Html msg)
viewExpectationResult expectation =
    getFailureReason expectation
        |> Maybe.map
            (\reason ->
                div []
                    [ pre [] [ text reason.description ]
                    , viewReason reason.reason
                    ]
            )


viewReason : Reason -> Html msg
viewReason reason =
    case reason of
        Custom ->
            text ""

        Equality expected actual ->
            "Expected: " ++ expected ++ " | Actual: " ++ actual |> text

        Comparison expected actual ->
            "Expected: " ++ expected ++ " | Actual: " ++ actual |> text

        ListDiff expected received ->
            viewListDiff expected received

        CollectionDiff details ->
            "Expected: " ++ details.expected ++ " | Actual: " ++ details.actual |> text

        TODO ->
            "TODO" |> text

        Invalid invalidReason ->
            viewInvalidReason invalidReason


viewListDiff : List String -> List String -> Html msg
viewListDiff expected actual =
    let
        expectedArray =
            Array.fromList expected

        actualArray =
            Array.fromList actual
    in
    div []
        [ text "The lists don't match! \u{1F631}"
        , div [ style "display" "flex" ]
            [ div [ style "margin-right" "5vw" ]
                [ text "Expected"
                , ul [] (List.indexedMap (viewListDiffPart actualArray) expected)
                ]
            , div []
                [ text "Actual"
                , ul [] (List.indexedMap (viewListDiffPart expectedArray) actual)
                ]
            ]
        ]


viewListDiffPart : Array String -> Int -> String -> Html msg
viewListDiffPart otherList index listPart =
    let
        styles =
            Array.get index otherList
                |> Maybe.andThen
                    (\value ->
                        if value == listPart then
                            Just value

                        else
                            Nothing
                    )
                |> Maybe.map (always [ style "color" "green" ])
                |> Maybe.withDefault [ style "color" "red", style "font-weight" "bold" ]
    in
    li styles [ text listPart ]


viewInvalidReason : InvalidReason -> Html msg
viewInvalidReason reason =
    case reason of
        EmptyList ->
            text "You should have at least one test in the list"

        NonpositiveFuzzCount ->
            text "The fuzz count must be positive"

        InvalidFuzzer ->
            text "The fuzzer used is invalid"

        BadDescription ->
            text "The description of your test is not valid"

        DuplicatedName ->
            text "At least two tests have the same name, please change at least one"

        DistributionInsufficient ->
            text "Distribution was insufficient"

        DistributionBug ->
            text "Distribution bug"
