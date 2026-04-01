module Tui.Effect exposing
    ( Effect
    , none, batch, perform, attempt, exit, exitWithCode
    , toast, errorToast
    , resetScroll, scrollTo, scrollDown, scrollUp, setSelectedIndex, selectFirst, focusPane
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

@docs none, batch, perform, attempt, exit, exitWithCode

@docs toast, errorToast

@docs resetScroll, scrollTo, scrollDown, scrollUp, setSelectedIndex, selectFirst, focusPane

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


{-| Show a normal toast (auto-dismisses after ~2 seconds). Fire and forget.

    Effect.toast "Saved!"

-}
toast : String -> Effect msg
toast =
    Internal.toast


{-| Show an error toast (auto-dismisses after ~4 seconds). Fire and forget.

    Effect.errorToast "Failed to save"

-}
errorToast : String -> Effect msg
errorToast =
    Internal.errorToast


{-| Reset the scroll position of a pane to the top.

    Effect.resetScroll "diff"

-}
resetScroll : String -> Effect msg
resetScroll =
    Internal.resetScroll


{-| Scroll a pane to a specific line offset.

    Effect.scrollTo "diff" 100

-}
scrollTo : String -> Int -> Effect msg
scrollTo =
    Internal.scrollTo


{-| Scroll a pane down by N lines (relative).

    Effect.scrollDown "diff" 10

-}
scrollDown : String -> Int -> Effect msg
scrollDown =
    Internal.scrollDown


{-| Scroll a pane up by N lines (relative).

    Effect.scrollUp "diff" 10

-}
scrollUp : String -> Int -> Effect msg
scrollUp =
    Internal.scrollUp


{-| Set the selected index of a selectable pane.

    Effect.setSelectedIndex "commits" 5

-}
setSelectedIndex : String -> Int -> Effect msg
setSelectedIndex =
    Internal.setSelectedIndex


{-| Reset selection to the first item in a pane.

    Effect.selectFirst "items"

-}
selectFirst : String -> Effect msg
selectFirst =
    Internal.selectFirst


{-| Move keyboard focus to a specific pane.

    Effect.focusPane "commits"

-}
focusPane : String -> Effect msg
focusPane =
    Internal.focusPane


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
    , toast : String -> a
    , errorToast : String -> a
    , resetScroll : String -> a
    , scrollTo : String -> Int -> a
    , scrollDown : String -> Int -> a
    , scrollUp : String -> Int -> a
    , setSelectedIndex : String -> Int -> a
    , selectFirst : String -> a
    , focusPane : String -> a
    }
    -> Effect msg
    -> a
fold =
    Internal.fold
