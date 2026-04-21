module TestElmWorker exposing (run)

{-| End-to-end smoke test for `BackendTask.Parallel.worker` /
`Parallel.runOn`. Spawns an Elm worker pool for the
[`SimpleSquareWorker`](SimpleSquareWorker) module, hands it a
1-byte shared multiplier, then dispatches several squaring tasks across
the pool and asserts the results.

Run via:

    (cd test-scripts && npx elm-pages run src/TestElmWorker.elm)

-}

import BackendTask exposing (BackendTask)
import BackendTask.Parallel
import Bytes
import Bytes.Decode
import Bytes.Encode
import FatalError
import Pages.Script as Script exposing (Script)


run : Script
run =
    (BackendTask.Parallel.worker
        { workerModule = "SimpleSquareWorker"
        , shared = Bytes.Encode.encode (Bytes.Encode.unsignedInt8 multiplier)
        }
        |> BackendTask.andThen
            (\w ->
                inputs
                    |> List.map (squareViaWorker w)
                    |> BackendTask.combine
            )
        |> BackendTask.andThen
            (\actuals ->
                let
                    expected : List Int
                    expected =
                        List.map (\n -> n * n * multiplier) inputs
                in
                if actuals == expected then
                    Script.log
                        ("TestElmWorker: 10 tasks round-tripped through SimpleSquareWorker ✓ "
                            ++ "(multiplier="
                            ++ String.fromInt multiplier
                            ++ ", results="
                            ++ String.join "," (List.map String.fromInt actuals)
                            ++ ")"
                        )

                else
                    BackendTask.fail
                        (FatalError.fromString
                            ("TestElmWorker mismatch:\n  expected: "
                                ++ String.join "," (List.map String.fromInt expected)
                                ++ "\n  got:      "
                                ++ String.join "," (List.map String.fromInt actuals)
                            )
                        )
            )
    )
        |> Script.withoutCliOptions


multiplier : Int
multiplier =
    3


inputs : List Int
inputs =
    [ 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 ]


squareViaWorker : BackendTask.Parallel.Worker -> Int -> BackendTask FatalError.FatalError Int
squareViaWorker w n =
    BackendTask.Parallel.runOn w
        (Bytes.Encode.encode (Bytes.Encode.unsignedInt32 Bytes.BE n))
        (Bytes.Decode.unsignedInt32 Bytes.BE)
