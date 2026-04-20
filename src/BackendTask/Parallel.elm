module BackendTask.Parallel exposing (run)

{-| Dispatch a `Bytes`-in / `Bytes`-out task to a pool of long-lived Node
Worker threads. Unlike [`BackendTask.Custom.runBytes`](BackendTask-Custom#runBytes),
which runs the port function on the main thread, `Parallel.run` dispatches
to a worker in a pool so concurrent calls actually execute in parallel
across CPU cores.

This is the building block for running CPU-bound workloads (binary
processing, serialized interpreter evaluations, etc.) without blocking the
main event loop. For use cases where the work is I/O bound, plain
`BackendTask.combine` already gets you main-thread-level concurrency.

@docs run


# Port function signature

The JavaScript port function has the same shape as
[`BackendTask.Custom.runBytes`](BackendTask-Custom#runBytes), but it runs
inside a Node Worker thread:

    // custom-backend-task.js
    export async function hashBytes(inputBytes, context) {
        // Runs in a worker thread; main thread stays responsive.
        const hash = await import("node:crypto").then((m) =>
            m.createHash("sha256").update(inputBytes).digest()
        );
        return hash;  // returned as bytes to the caller
    }

Combine many `Parallel.run` calls with `BackendTask.combine` to get actual
parallel execution:

    import BackendTask.Parallel

    hashAll : List Bytes -> BackendTask FatalError (List Bytes)
    hashAll inputs =
        inputs
            |> List.map
                (\bytes ->
                    BackendTask.Parallel.run
                        "hashBytes"
                        bytes
                        (Bytes.Decode.bytes 32)
                )
            |> BackendTask.combine


# Pool size and lifecycle

The pool is brought up lazily on the first `Parallel.run` call in an
`elm-pages run` invocation and torn down when the process exits. Its size
defaults to `os.cpus().length`. Workers each load the project's
`custom-backend-task.js`, so any top-level state in that file is duplicated
per worker — keep worker port functions referentially transparent where
possible.

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Bytes exposing (Bytes)
import Bytes.Decode
import FatalError exposing (FatalError)


{-| Dispatch a task to the worker pool. Blocks (as a `BackendTask`) until
the worker returns its result.

`portName` refers to an exported async function in
`custom-backend-task.js`, just like [`BackendTask.Custom.runBytes`](BackendTask-Custom#runBytes).

-}
run :
    String
    -> Bytes
    -> Bytes.Decode.Decoder output
    -> BackendTask FatalError output
run portName input decoder =
    BackendTask.Internal.Request.requestBytes
        { name = "parallel-port-bytes/" ++ portName
        , body = BackendTask.Http.bytesBody "application/octet-stream" input
        , expect = decoder
        }
