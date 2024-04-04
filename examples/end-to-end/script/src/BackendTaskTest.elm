module BackendTaskTest exposing (run, testScript)

import Array exposing (Array)
import BackendTask exposing (BackendTask)
import BackendTask.Random
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import List.Extra
import Pages.Script as Script exposing (Script)
import Random
import Test exposing (Test)
import Test.Runner exposing (getFailureReason)
import Test.Runner.Failure exposing (InvalidReason, Reason(..))


testScript : String -> List (BackendTask FatalError Test.Test) -> Script
testScript suiteName testCases =
    testCases
        |> BackendTask.sequence
        |> BackendTask.map (Test.describe suiteName)
        |> run
        |> Script.withoutCliOptions


run : BackendTask FatalError Test -> BackendTask FatalError ()
run toTest =
    BackendTask.Random.int32
        |> BackendTask.map Random.initialSeed
        |> BackendTask.andThen
            (\seed ->
                toTest
                    |> BackendTask.andThen
                        (\testCase ->
                            case Test.Runner.fromTest 1 seed testCase of
                                Test.Runner.Plain tests ->
                                    case toFailures tests of
                                        [] ->
                                            Script.log "All tests passed!"

                                        failures ->
                                            BackendTask.fail
                                                (FatalError.build
                                                    { title = "Test suite failed"
                                                    , body =
                                                        failures
                                                            |> List.map
                                                                (\( label, failure ) ->
                                                                    label ++ " | " ++ failure
                                                                )
                                                            |> String.join "\n"
                                                    }
                                                )

                                Test.Runner.Only tests ->
                                    case toFailures tests of
                                        [] ->
                                            BackendTask.fail
                                                (FatalError.build
                                                    { title = "Passed With Only"
                                                    , body = "The test suite passed, but only was used."
                                                    }
                                                )

                                        failures ->
                                            BackendTask.fail
                                                (FatalError.build
                                                    { title = "Test suite failed"
                                                    , body =
                                                        failures
                                                            |> List.map
                                                                (\( label, failure ) ->
                                                                    label ++ " | " ++ failure
                                                                )
                                                            |> String.join "\n"
                                                    }
                                                )

                                Test.Runner.Skipping tests ->
                                    case toFailures tests of
                                        [] ->
                                            BackendTask.fail
                                                (FatalError.build
                                                    { title = "Passed With Skip"
                                                    , body = "The test suite passed, but some tests were skipped."
                                                    }
                                                )

                                        failures ->
                                            BackendTask.fail
                                                (FatalError.build
                                                    { title = "Test suite failed"
                                                    , body =
                                                        failures
                                                            |> List.map
                                                                (\( label, failure ) ->
                                                                    label ++ " | " ++ failure
                                                                )
                                                            |> String.join "\n"
                                                    }
                                                )

                                Test.Runner.Invalid string ->
                                    BackendTask.fail
                                        (FatalError.build
                                            { title = "Invalid test suite"
                                            , body = string
                                            }
                                        )
                        )
            )


toFailures tests =
    let
        resultsWithLabels : List ( String, Expectation )
        resultsWithLabels =
            List.Extra.zip
                (tests |> List.concatMap (\test -> test.labels))
                (tests |> List.concatMap (\test -> test.run ()))

        failures : List ( String, Maybe String )
        failures =
            resultsWithLabels
                |> List.map
                    (Tuple.mapSecond
                        (\thing ->
                            thing
                                |> getFailureReason
                                |> Maybe.map
                                    (\failure ->
                                        viewReason failure.reason
                                    )
                        )
                    )

        onlyFailures : List ( String, String )
        onlyFailures =
            List.filterMap
                (\( label, maybeFailure ) ->
                    case maybeFailure of
                        Just failure ->
                            Just ( label, failure )

                        Nothing ->
                            Nothing
                )
                failures
    in
    onlyFailures


viewReason : Reason -> String
viewReason reason =
    case reason of
        Custom ->
            ""

        Equality expected actual ->
            "Expected: " ++ expected ++ " | Actual: " ++ actual

        Comparison expected actual ->
            "Expected: " ++ expected ++ " | Actual: " ++ actual

        ListDiff expected received ->
            viewListDiff expected received

        CollectionDiff details ->
            "Expected: " ++ details.expected ++ " | Actual: " ++ details.actual

        TODO ->
            "TODO"

        Invalid invalidReason ->
            viewInvalidReason invalidReason


viewInvalidReason : InvalidReason -> String
viewInvalidReason reason =
    case reason of
        Test.Runner.Failure.EmptyList ->
            "You should have at least one test in the list"

        Test.Runner.Failure.NonpositiveFuzzCount ->
            "The fuzz count must be positive"

        Test.Runner.Failure.InvalidFuzzer ->
            "The fuzzer used is invalid"

        Test.Runner.Failure.BadDescription ->
            "The description of your test is not valid"

        Test.Runner.Failure.DuplicatedName ->
            "At least two tests have the same name, please change at least one"

        Test.Runner.Failure.DistributionInsufficient ->
            "The distribution is not sufficient"

        Test.Runner.Failure.DistributionBug ->
            "The distribution is not correct"


viewListDiff : List String -> List String -> String
viewListDiff expected actual =
    let
        expectedArray : Array String
        expectedArray =
            Array.fromList expected

        actualArray : Array String
        actualArray =
            Array.fromList actual
    in
    "The lists don't match!"
        ++ "Expected"
        ++ (List.indexedMap (viewListDiffPart actualArray) expected |> String.join " ")
        ++ "Actual"
        ++ (List.indexedMap (viewListDiffPart expectedArray) actual |> String.join " ")


viewListDiffPart : Array String -> Int -> String -> String
viewListDiffPart otherList index listPart =
    let
        green : Bool
        green =
            Array.get index otherList
                |> maybeFilter (\value -> value == listPart)
                |> Maybe.map (always True)
                |> Maybe.withDefault False
    in
    -- todo use `green` to set ansi color code for green or red
    listPart


maybeFilter : (a -> Bool) -> Maybe a -> Maybe a
maybeFilter f m =
    case m of
        Just a ->
            if f a then
                m

            else
                Nothing

        Nothing ->
            Nothing
