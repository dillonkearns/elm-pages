module BackendTask.Parallel exposing
    ( run
    , Worker, worker, runOn
    , initShared, receiveTask, sendResult
    )

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


# Spawning Elm-in-worker pools

For workloads where each unit of work is itself an Elm computation
(running an interpreter, evaluating tests, etc.), it is much faster to
share a one-time payload (`shared`) across many tasks than to redo that
setup per task. The `worker` / `runOn` pair lets a main script spawn a
pool of long-lived worker threads — each of which boots a compiled Elm
script — and then dispatch many small tasks to that pool.

The worker module is a regular Elm-pages [`Pages.Script`](Pages-Script#Script)
in the project's source-directories. It receives the shared payload via
[`initShared`](#initShared), then loops calling [`receiveTask`](#receiveTask)
and [`sendResult`](#sendResult). Example main script:

    main : Script
    main =
        BackendTask.Parallel.worker
            { workerModule = "TestFileWorker"
            , shared = encodeProject project
            }
            |> BackendTask.andThen
                (\w ->
                    files
                        |> List.map
                            (\f ->
                                BackendTask.Parallel.runOn w
                                    (encodeFile f)
                                    fileResultDecoder
                            )
                        |> BackendTask.combine
                )
            |> Script.withoutCliOptions

@docs Worker, worker, runOn


# Worker-script primitives

The following primitives are designed to be called from an Elm script that
runs **inside** a worker thread (an "Elm worker"). They let the script
receive a one-time shared payload, then loop receiving per-task input and
sending results, while the worker stays alive between tasks.

@docs initShared, receiveTask, sendResult


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
import Bytes.Encode
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


{-| An opaque handle to a pool of Elm worker threads, returned by
[`worker`](#worker) and consumed by [`runOn`](#runOn).

Internally, the handle just remembers which worker module the pool was
spawned for; the actual worker threads live on the JS side, indexed by
that module name.

-}
type Worker
    = Worker String


{-| Spawn (or attach to) a pool of long-lived Elm worker threads for the
given Elm module, and pass them the one-time shared payload.

The pool is brought up lazily on the first `worker` call for a given
`workerModule`; subsequent calls for the same module attach to the
existing pool and re-broadcast the new shared payload (so calling
`worker` again with a fresh payload effectively rebuilds the pool's
shared state). Workers persist for the lifetime of `elm-pages run`.

`workerModule` must name an Elm module in your project's
source-directories that exposes `run : Pages.Script.Script`. The script
should call `initShared` once and then loop calling `receiveTask` /
`sendResult`.

-}
worker :
    { workerModule : String
    , shared : Bytes
    , poolSize : Maybe Int
    }
    -> BackendTask FatalError Worker
worker { workerModule, shared, poolSize } =
    BackendTask.Internal.Request.requestBytesWithHeaders
        { name = "parallel-spawn-worker/" ++ workerModule
        , headers =
            -- `pool-size` is a HINT (clamped to `min(hint, cpus)` JS-side).
            -- Setting it lets callers right-size the worker pool to their
            -- actual workload; the default `min(cpus, 16)` is wasteful for
            -- small dispatch counts (each worker pays a fixed bundle-parse
            -- cost on spawn that doesn't amortize with fewer than ~one
            -- task per worker).
            case poolSize of
                Just n ->
                    [ ( "pool-size", String.fromInt n ) ]

                Nothing ->
                    []
        , body = BackendTask.Http.bytesBody "application/octet-stream" shared
        , expect = Bytes.Decode.succeed (Worker workerModule)
        }


{-| Dispatch a single task to the pool for this `Worker`, blocking (as a
`BackendTask`) until any free worker in the pool returns the result.

Combine with `BackendTask.combine` to fan out many tasks across the pool
in parallel:

    files
        |> List.map (\f -> runOn w (encodeFile f) decodeResult)
        |> BackendTask.combine

-}
runOn :
    Worker
    -> Bytes
    -> Bytes.Decode.Decoder output
    -> BackendTask FatalError output
runOn (Worker workerModule) input decoder =
    BackendTask.Internal.Request.requestBytes
        { name = "parallel-worker-task/" ++ workerModule
        , body = BackendTask.Http.bytesBody "application/octet-stream" input
        , expect = decoder
        }


{-| Receive the one-time shared payload that was passed to the worker when
it was spawned. Designed to be called once at the start of an Elm worker
script, before entering the per-task receive loop.

The shared payload is delivered by the parent thread that spawned the
worker (via `Parallel.worker { shared = … }`); each worker resolves
`initShared` exactly once.

-}
initShared : Bytes.Decode.Decoder shared -> BackendTask FatalError shared
initShared decoder =
    BackendTask.Internal.Request.requestBytes
        { name = "parallel-worker-init-shared"
        , body = BackendTask.Http.bytesBody "application/octet-stream" emptyBytes
        , expect = decoder
        }


{-| Block until the parent thread dispatches a task to this worker, then
resolve with the task's input bytes (decoded). Designed to be called in a
loop inside an Elm worker script — each call corresponds to one
`Parallel.runOn` from the parent.
-}
receiveTask : Bytes.Decode.Decoder input -> BackendTask FatalError input
receiveTask decoder =
    BackendTask.Internal.Request.requestBytes
        { name = "parallel-worker-receive-task"
        , body = BackendTask.Http.bytesBody "application/octet-stream" emptyBytes
        , expect = decoder
        }


{-| Hand a task result back to the parent thread. The bytes are delivered
to whoever called `Parallel.runOn` for the matching task; this resolves
with `()` once the parent has acknowledged receipt.
-}
sendResult : Bytes -> BackendTask FatalError ()
sendResult output =
    BackendTask.Internal.Request.requestBytes
        { name = "parallel-worker-send-result"
        , body = BackendTask.Http.bytesBody "application/octet-stream" output
        , expect = Bytes.Decode.succeed ()
        }


emptyBytes : Bytes
emptyBytes =
    Bytes.Encode.encode (Bytes.Encode.sequence [])
