module BackendTaskTests exposing (combine, sequence)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Test exposing (Test, test)
import Test.BackendTask


size : number
size =
    100


sequence : Test
sequence =
    test "BackendTask.sequence respects order" <|
        \() ->
            List.range 1 size
                |> List.map BackendTask.succeed
                |> BackendTask.sequence
                |> expectEqual (List.range 1 size)
                |> Test.BackendTask.fromBackendTask
                |> Test.BackendTask.expectSuccess


combine : Test
combine =
    test "BackendTask.combine respects order" <|
        \() ->
            List.range 1 size
                |> List.map BackendTask.succeed
                |> BackendTask.combine
                |> expectEqual (List.range 1 size)
                |> Test.BackendTask.fromBackendTask
                |> Test.BackendTask.expectSuccess


expectEqual : v -> BackendTask FatalError v -> BackendTask FatalError ()
expectEqual expected =
    BackendTask.andThen
        (\actual ->
            if expected == actual then
                BackendTask.succeed ()

            else
                BackendTask.fail (FatalError.fromString ("Expected " ++ Debug.toString expected ++ ", got " ++ Debug.toString actual))
        )
