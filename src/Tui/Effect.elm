module Tui.Effect exposing
    ( Effect
    , perform, attempt
    , none, batch, map
    , exit, exitWithCode
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

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Tui.Effect.Internal as Internal


{-| An `Effect` can be passed to `update` or `init`. Like the `Cmd` part of a standard
Elm TEA application.
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


{-| Run a `BackendTask` and get the resolved data back in a `Msg`. If the
`BackendTask` fails, the `FatalError` propogates and the TUI exits and prints
the `FatalError`'s message.

    Script.command "git" [ "status", "--porcelain" ]
        |> BackendTask.map parseFiles
        |> Effect.perform GotFiles

-}
perform : (a -> msg) -> BackendTask FatalError a -> Effect msg
perform =
    Internal.perform


{-| Like `perform`, but surfaces errors as `Result` values for you to handle `BackendTask` errors gracefully.

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

Useful in combination with [`BackendTask.mapError`](BackendTask#mapError).

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
