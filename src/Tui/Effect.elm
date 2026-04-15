module Tui.Effect exposing
    ( Effect
    , perform, attempt
    , none, batch, map
    , exit, exitWithCode
    , fold
    )

{-| The core Effects for [`Tui.Program`](Tui#Program)s.
Most notably, your TUI can resolve a [`BackendTask`](BackendTask)
within its `init` and `update` and get back the result
as a `Msg`.

    update : Msg -> Model -> ( Model, Effect Msg )
    update msg model =
        case msg of
            PressedStage file ->
                ( { model | staging = Just file }
                , Script.exec "git" [ "add", file ]
                    |> Effect.perform (\() -> StagingComplete file)
                )

            StagingComplete file ->
                ( { model | staging = Nothing }
                , Effect.none
                )

@docs Effect


## Performing `BackendTask`s

@docs perform, attempt


## Combining and Transforming

@docs none, batch, map


## Exiting Program

@docs exit, exitWithCode


## Internal

Low-level framework hook for companion packages (like `tui-widgets`

@docs fold

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Tui.Effect.Internal as Internal


{-| An effect produced by `update` or `init`. Wraps `BackendTask` execution,
exit, and batching.
-}
type alias Effect msg =
    Internal.Effect msg


{-| No effect.
-}
none : Effect msg
none =
    Internal.none


{-| Combine multiple effects sequentially.
-}
batch : List (Effect msg) -> Effect msg
batch =
    Internal.batch


{-| Run a `BackendTask` and produce a message with the result. If the
`BackendTask` fails with a `FatalError`, the TUI exits with an error message
(terminal state is restored first).

    Script.command "git" [ "status", "--porcelain" ]
        |> BackendTask.map parseFiles
        |> Effect.perform GotFiles

-}
perform : (a -> msg) -> BackendTask FatalError a -> Effect msg
perform =
    Internal.perform


{-| Like `perform`, but surfaces errors as `Result` values for you to handle.

    Script.command "git" [ "diff", file ]
        |> BackendTask.mapError (\_ -> "git diff failed")
        |> Effect.attempt
            (\result ->
                case result of
                    Ok text ->
                        GotDiff text

                    Err reason ->
                        DiffFailed reason
            )

Polymorphic in the error type. When you want to rescue failures into your
own `Msg`, the error you care about is almost never an opaque `FatalError`
— it's whatever shape is meaningful to your code. Use
[`BackendTask.mapError`](BackendTask#mapError) (or a custom recoverable
error) to shape it before passing to `attempt`.

-}
attempt : (Result error a -> msg) -> BackendTask error a -> Effect msg
attempt =
    Internal.attempt


{-| Exit the TUI (exit code 0). Terminal state is restored.
-}
exit : Effect msg
exit =
    Internal.exit


{-| Exit the TUI with a specific exit code. Terminal state is restored.
-}
exitWithCode : Int -> Effect msg
exitWithCode =
    Internal.exitWithCode


{-| Transform the message type of an effect.
-}
map : (a -> b) -> Effect a -> Effect b
map =
    Internal.map


{-| Inspect an opaque `Effect` without exposing its constructors. Mainly useful for framework authors.
-}
fold :
    { none : a
    , batch : List (Effect msg) -> a
    , backendTask : BackendTask FatalError msg -> a
    , exit : Int -> a
    }
    -> Effect msg
    -> a
fold =
    Internal.fold
