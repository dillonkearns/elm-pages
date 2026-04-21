module SimpleSquareWorker exposing (run)

{-| Worker-side script for the B.2/B.3 end-to-end test. Receives a
1-byte multiplier as the shared payload, then loops squaring the per-task
u32 input × the multiplier and sending the result back.

This module isn't run directly with `npx elm-pages run` — it's compiled
into `elm-stuff/elm-pages/workers/SimpleSquareWorker.cjs` by the
elm-pages worker pool when the parent script calls
`BackendTask.Parallel.worker { workerModule = "SimpleSquareWorker", … }`.

-}

import BackendTask exposing (BackendTask)
import BackendTask.Parallel
import Bytes
import Bytes.Decode
import Bytes.Encode
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)


run : Script
run =
    (BackendTask.Parallel.initShared sharedDecoder
        |> BackendTask.andThen workerLoop
    )
        |> Script.withoutCliOptions


sharedDecoder : Bytes.Decode.Decoder Int
sharedDecoder =
    Bytes.Decode.unsignedInt8


workerLoop : Int -> BackendTask FatalError ()
workerLoop multiplier =
    BackendTask.Parallel.receiveTask u32BE
        |> BackendTask.andThen
            (\input ->
                let
                    output : Int
                    output =
                        busyWait 50 (input * input * multiplier)
                in
                BackendTask.Parallel.sendResult
                    (Bytes.Encode.encode (Bytes.Encode.unsignedInt32 Bytes.BE output))
            )
        |> BackendTask.andThen (\_ -> workerLoop multiplier)


{-| Spin for the requested number of arithmetic iterations as a stand-in
for real CPU work. Used to verify that tasks actually run in parallel
across worker threads.
-}
busyWait : Int -> Int -> Int
busyWait iterations initial =
    let
        loop : Int -> Int -> Int
        loop n acc =
            if n <= 0 then
                acc

            else
                loop (n - 1) (acc + (n * 17))
    in
    loop (iterations * 100000) initial - busyWaitOffset iterations


busyWaitOffset : Int -> Int
busyWaitOffset iterations =
    let
        loop : Int -> Int -> Int
        loop n acc =
            if n <= 0 then
                acc

            else
                loop (n - 1) (acc + (n * 17))
    in
    loop (iterations * 100000) 0


u32BE : Bytes.Decode.Decoder Int
u32BE =
    Bytes.Decode.unsignedInt32 Bytes.BE
