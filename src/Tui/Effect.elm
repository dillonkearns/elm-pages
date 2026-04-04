module Tui.Effect exposing
    ( Effect
    , Toast, info, error, toastMessage, toastIsError
    , none, batch, perform, attempt, exit, exitWithCode
    , toast
    , map, fold
    )

{-| Effects for TUI scripts. The bridge between `BackendTask` and the TUI
update cycle.

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

`Effect` is opaque. Most apps only need the smart constructors like
[`perform`](#perform), [`batch`](#batch), and [`toast`](#toast).

@docs Effect


## Toast

@docs Toast, info, error, toastMessage, toastIsError


## Core Effects

@docs none, batch, perform, attempt, exit, exitWithCode

@docs toast

@docs map, fold

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


{-| Combine multiple effects. Effects run sequentially — if an effect produces
a message (via `perform`/`attempt`), remaining effects are skipped and the
message is fed back into `update`.
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


{-| Like `perform`, but the user handles errors via `Result`.

    Script.command "git" [ "diff", file ]
        |> Effect.attempt
            (\result ->
                case result of
                    Ok text ->
                        GotDiff text

                    Err err ->
                        DiffFailed err
            )

-}
attempt : (Result FatalError a -> msg) -> BackendTask FatalError a -> Effect msg
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


{-| Opaque toast configuration. Build with [`info`](#info) or [`error`](#error).

    Effect.toast (Effect.info "Saved!")
    Effect.toast (Effect.error "Failed to save")

-}
type alias Toast =
    Internal.Toast


{-| Create an informational toast.

    Effect.toast (Effect.info "Saved!")

-}
info : String -> Toast
info =
    Internal.info


{-| Create an error toast.

    Effect.toast (Effect.error "Failed to save")

-}
error : String -> Toast
error =
    Internal.error


{-| Get the message text from a toast. Useful when interpreting effects via
[`fold`](#fold).
-}
toastMessage : Toast -> String
toastMessage =
    Internal.toastMessage


{-| Check whether a toast is an error toast. Useful when interpreting effects via
[`fold`](#fold).
-}
toastIsError : Toast -> Bool
toastIsError =
    Internal.toastIsError


{-| Show a toast notification. Fire and forget.

    Effect.toast (Effect.info "Saved!")
    Effect.toast (Effect.error "Failed to save")

-}
toast : Toast -> Effect msg
toast =
    Internal.toast



{-| Transform the message type of an effect.
-}
map : (a -> b) -> Effect a -> Effect b
map =
    Internal.map


{-| Inspect an opaque `Effect` without exposing its constructors.

This is mainly useful for advanced integrations like companion packages and
test tooling that need to interpret effects while keeping the end-user API
clean.
-}
fold :
    { none : a
    , batch : List (Effect msg) -> a
    , backendTask : BackendTask FatalError msg -> a
    , exit : Int -> a
    , toast : Toast -> a
    }
    -> Effect msg
    -> a
fold =
    Internal.fold
