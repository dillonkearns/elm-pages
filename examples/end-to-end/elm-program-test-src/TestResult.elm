module TestResult exposing (TestResult, andThen, fail)

import ProgramTest.Failure exposing (Failure)
import TestState exposing (TestState)


{-| TODO: what's a better name?
-}
type alias TestResult model msg effect =
    Result
        { reason : Failure
        }
        (TestState model msg effect)


fail : Failure -> TestState model msg effect -> TestResult model msg effect
fail failure state =
    Err
        { reason = failure
        }


andThen : (TestState model msg effect -> Result Failure (TestState model msg effect)) -> TestResult model msg effect -> TestResult model msg effect
andThen f testResult =
    case testResult of
        Ok state ->
            case f state of
                Err failure ->
                    fail failure state

                Ok newState ->
                    Ok newState

        Err _ ->
            testResult
