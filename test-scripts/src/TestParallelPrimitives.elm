module TestParallelPrimitives exposing (run)

{-| B.1 smoke test for the worker-script primitives in
`BackendTask.Parallel`.

This script doesn't actually spawn a worker; it just exercises the wire
format end-to-end against the B.1 stubs in `generator/src/request-cache.js`:

  - `initShared` resolves with empty bytes (decoder must accept that).
  - `receiveTask` resolves with a 4-byte u32 sentinel (42).
  - `sendResult` accepts arbitrary bytes and resolves with `()`.

If this runs without error, the Elm side of the primitives compiles and
the request plumbing routes the new URLs correctly. The full round-trip
(real shared payload + real per-task input/output) lands in B.3.

Run via:

    (cd test-scripts && npx elm-pages run src/TestParallelPrimitives.elm)

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
    (BackendTask.Parallel.initShared (Bytes.Decode.succeed ())
        |> BackendTask.andThen (\_ -> Script.log "  ✓ initShared resolved")
        |> BackendTask.andThen (\_ -> recvAndCheck 1)
        |> BackendTask.andThen (\_ -> recvAndCheck 2)
        |> BackendTask.andThen (\_ -> recvAndCheck 3)
        |> BackendTask.andThen (\_ -> Script.log "  ✓ 3 sequential receiveTask calls each fired (no cross-batch dedup)")
        |> BackendTask.andThen
            (\_ ->
                BackendTask.Parallel.sendResult
                    (Bytes.Encode.encode (Bytes.Encode.unsignedInt32 Bytes.BE 7))
            )
        |> BackendTask.andThen (\_ -> Script.log "  ✓ sendResult resolved")
        |> BackendTask.andThen
            (\_ ->
                Script.log "TestParallelPrimitives: all checks passed ✓"
            )
    )
        |> Script.withoutCliOptions


recvAndCheck : Int -> BackendTask FatalError.FatalError ()
recvAndCheck callIx =
    BackendTask.Parallel.receiveTask u32BE
        |> BackendTask.andThen
            (\value ->
                if value == 42 then
                    BackendTask.succeed ()

                else
                    BackendTask.fail
                        (FatalError.fromString
                            ("receiveTask call #"
                                ++ String.fromInt callIx
                                ++ " expected 42, got "
                                ++ String.fromInt value
                            )
                        )
            )


u32BE : Bytes.Decode.Decoder Int
u32BE =
    Bytes.Decode.unsignedInt32 Bytes.BE
