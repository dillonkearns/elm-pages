module TestParallel exposing (run)

{-| End-to-end smoke test for `BackendTask.Parallel.run`.

Dispatches 10 `squareU32` tasks in parallel (each with a 50 ms busy-wait).
If the worker pool actually runs tasks concurrently across threads, wall
time should be much less than 10 × 50 ms = 500 ms. Also calls `reportThread`
10 times and asserts that at least 2 distinct thread IDs appear (otherwise
everything ran on one worker).

Run via:

    (cd test-scripts && npx elm-pages run src/TestParallel.elm)

-}

import BackendTask exposing (BackendTask)
import BackendTask.Parallel
import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import FatalError
import Pages.Script as Script exposing (Script)


run : Script
run =
    (squaresCheck
        |> BackendTask.andThen (\_ -> threadsCheck)
        |> BackendTask.andThen (\_ -> Script.log "TestParallel: all checks passed ✓")
    )
        |> Script.withoutCliOptions


inputs : List Int
inputs =
    [ 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 ]


squaresCheck : BackendTask FatalError.FatalError ()
squaresCheck =
    inputs
        |> List.map square
        |> BackendTask.combine
        |> BackendTask.andThen
            (\actualSquares ->
                let
                    expected =
                        List.map (\n -> n * n) inputs
                in
                if actualSquares == expected then
                    Script.log
                        ("  ✓ 10 squareU32 calls round-tripped correctly: "
                            ++ String.join ", " (List.map String.fromInt actualSquares)
                        )

                else
                    BackendTask.fail
                        (FatalError.fromString
                            ("TestParallel squares failed\n  expected: "
                                ++ String.join "," (List.map String.fromInt expected)
                                ++ "\n  got     : "
                                ++ String.join "," (List.map String.fromInt actualSquares)
                            )
                        )
            )


square : Int -> BackendTask FatalError.FatalError Int
square n =
    BackendTask.Parallel.run "squareU32"
        (Bytes.Encode.encode (Bytes.Encode.unsignedInt32 Bytes.BE n))
        (Bytes.Decode.unsignedInt32 Bytes.BE)


threadsCheck : BackendTask FatalError.FatalError ()
threadsCheck =
    List.range 1 10
        |> List.map reportThread
        |> BackendTask.combine
        |> BackendTask.andThen
            (\threadIds ->
                let
                    distinct =
                        threadIds
                            |> List.foldl
                                (\x acc ->
                                    if List.member x acc then
                                        acc

                                    else
                                        x :: acc
                                )
                                []
                in
                if List.length distinct >= 2 then
                    Script.log
                        ("  ✓ "
                            ++ String.fromInt (List.length threadIds)
                            ++ " reportThread calls saw "
                            ++ String.fromInt (List.length distinct)
                            ++ " distinct worker threads"
                        )

                else
                    BackendTask.fail
                        (FatalError.fromString
                            ("TestParallel: expected ≥2 distinct worker threads, got "
                                ++ String.fromInt (List.length distinct)
                                ++ " (ids="
                                ++ String.join "," (List.map String.fromInt threadIds)
                                ++ ")"
                            )
                        )
            )


{-| Pass the call index in the input bytes so each request has a unique hash
(elm-pages deduplicates requests with identical URL+headers+body).
-}
reportThread : Int -> BackendTask FatalError.FatalError Int
reportThread nonce =
    BackendTask.Parallel.run "reportThread"
        (Bytes.Encode.encode (Bytes.Encode.unsignedInt32 Bytes.BE nonce))
        (Bytes.Decode.unsignedInt32 Bytes.BE)
