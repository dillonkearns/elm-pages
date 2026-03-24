module Tui.Effect exposing
    ( Effect(..)
    , none, batch, perform, attempt, exit, exitWithCode
    , toast, errorToast
    , resetScroll, scrollTo, scrollDown, scrollUp, setSelectedIndex, selectFirst, focusPane
    , map
    , EffectResult(..), toBackendTask
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

@docs Effect

@docs none, batch, perform, attempt, exit, exitWithCode

@docs toast, errorToast

@docs resetScroll, scrollTo, scrollDown, scrollUp, setSelectedIndex, selectFirst, focusPane

@docs map


## Internal

Used by the framework and test harness. You should not need these directly.

@docs EffectResult, toBackendTask

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)


{-| An effect produced by `update` or `init`. Wraps `BackendTask` execution,
exit, and batching.
-}
type Effect msg
    = None
    | Batch (List (Effect msg))
    | RunBackendTask (BackendTask FatalError msg)
    | SuspendBackendTask (BackendTask FatalError msg)
    | Exit
    | ExitWithCode Int
    | Toast String
    | ErrorToast String
    | ResetScroll String
    | ScrollTo String Int
    | ScrollDown String Int
    | ScrollUp String Int
    | SetSelectedIndex String Int
    | SelectFirst String
    | FocusPane String


{-| No effect.
-}
none : Effect msg
none =
    None


{-| Combine multiple effects. Effects run sequentially — if an effect produces
a message (via `perform`/`attempt`), remaining effects are skipped and the
message is fed back into `update`.
-}
batch : List (Effect msg) -> Effect msg
batch =
    Batch


{-| Run a `BackendTask` and produce a message with the result. If the
`BackendTask` fails with a `FatalError`, the TUI exits with an error message
(terminal state is restored first).

    Script.command "git" [ "status", "--porcelain" ]
        |> BackendTask.map parseFiles
        |> Effect.perform GotFiles

-}
perform : (a -> msg) -> BackendTask FatalError a -> Effect msg
perform toMsg bt =
    RunBackendTask (BackendTask.map toMsg bt)


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
attempt toMsg bt =
    RunBackendTask
        (bt
            |> BackendTask.map (\a -> toMsg (Ok a))
            |> BackendTask.onError (\err -> BackendTask.succeed (toMsg (Err err)))
        )


{-| Exit the TUI (exit code 0). Terminal state is restored.
-}
exit : Effect msg
exit =
    Exit


{-| Exit the TUI with a specific exit code. Terminal state is restored.
-}
exitWithCode : Int -> Effect msg
exitWithCode =
    ExitWithCode


{-| Show a normal toast (auto-dismisses after ~2 seconds). Fire and forget.

    Effect.toast "Saved!"

-}
toast : String -> Effect msg
toast =
    Toast


{-| Show an error toast (auto-dismisses after ~4 seconds). Fire and forget.

    Effect.errorToast "Failed to save"

-}
errorToast : String -> Effect msg
errorToast =
    ErrorToast


{-| Reset the scroll position of a pane to the top.

    Effect.resetScroll "diff"

-}
resetScroll : String -> Effect msg
resetScroll =
    ResetScroll


{-| Scroll a pane to a specific line offset.

    Effect.scrollTo "diff" 100

-}
scrollTo : String -> Int -> Effect msg
scrollTo =
    ScrollTo


{-| Scroll a pane down by N lines (relative).

    Effect.scrollDown "diff" 10

-}
scrollDown : String -> Int -> Effect msg
scrollDown =
    ScrollDown


{-| Scroll a pane up by N lines (relative).

    Effect.scrollUp "diff" 10

-}
scrollUp : String -> Int -> Effect msg
scrollUp =
    ScrollUp


{-| Set the selected index of a selectable pane.

    Effect.setSelectedIndex "commits" 5

-}
setSelectedIndex : String -> Int -> Effect msg
setSelectedIndex =
    SetSelectedIndex


{-| Reset selection to the first item in a pane.

    Effect.selectFirst "items"

-}
selectFirst : String -> Effect msg
selectFirst =
    SelectFirst


{-| Move keyboard focus to a specific pane.

    Effect.focusPane "commits"

-}
focusPane : String -> Effect msg
focusPane =
    FocusPane


{- INTERNAL: suspend is not yet implemented — the SuspendBackendTask
   constructor exists for future use but currently behaves identically
   to RunBackendTask. Not exposed in the public API.
-}


{-| Transform the message type of an effect.
-}
map : (a -> b) -> Effect a -> Effect b
map f effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        None ->
            None

        Batch effects ->
            Batch (List.map (map f) effects)

        RunBackendTask bt ->
            RunBackendTask (BackendTask.map f bt)

        SuspendBackendTask bt ->
            SuspendBackendTask (BackendTask.map f bt)

        Exit ->
            Exit

        ExitWithCode code ->
            ExitWithCode code

        Toast message ->
            Toast message

        ErrorToast message ->
            ErrorToast message

        ResetScroll paneId ->
            ResetScroll paneId

        ScrollTo paneId offset ->
            ScrollTo paneId offset

        ScrollDown paneId amount ->
            ScrollDown paneId amount

        ScrollUp paneId amount ->
            ScrollUp paneId amount

        SetSelectedIndex paneId index ->
            SetSelectedIndex paneId index

        SelectFirst paneId ->
            SelectFirst paneId

        FocusPane paneId ->
            FocusPane paneId



-- INTERNAL


{-| The result of processing an effect. Used internally by the TUI loop and
test harness.
-}
type EffectResult msg
    = EffectDone
    | EffectMsg msg
    | EffectExit Int


{-| Convert an Effect to a BackendTask that processes it and returns the result.
Used internally by the TUI loop.
-}
toBackendTask : Effect msg -> BackendTask FatalError (EffectResult msg)
toBackendTask effect =
    case effect of
        None ->
            BackendTask.succeed EffectDone

        Exit ->
            BackendTask.succeed (EffectExit 0)

        ExitWithCode code ->
            BackendTask.succeed (EffectExit code)

        RunBackendTask bt ->
            bt |> BackendTask.map EffectMsg

        SuspendBackendTask bt ->
            -- TODO: for PoC, suspend runs the same as perform
            -- A real implementation would send a "tui-suspend" request first
            bt |> BackendTask.map EffectMsg

        Batch effects ->
            processBatch effects

        Toast _ ->
            BackendTask.succeed EffectDone

        ErrorToast _ ->
            BackendTask.succeed EffectDone

        ResetScroll _ ->
            BackendTask.succeed EffectDone

        ScrollTo _ _ ->
            BackendTask.succeed EffectDone

        ScrollDown _ _ ->
            BackendTask.succeed EffectDone

        ScrollUp _ _ ->
            BackendTask.succeed EffectDone

        SetSelectedIndex _ _ ->
            BackendTask.succeed EffectDone

        SelectFirst _ ->
            BackendTask.succeed EffectDone

        FocusPane _ ->
            BackendTask.succeed EffectDone


processBatch : List (Effect msg) -> BackendTask FatalError (EffectResult msg)
processBatch effects =
    -- elm-review: known-unoptimized-recursion
    case effects of
        [] ->
            BackendTask.succeed EffectDone

        eff :: rest ->
            toBackendTask eff
                |> BackendTask.andThen
                    (\result ->
                        case result of
                            EffectDone ->
                                processBatch rest

                            EffectMsg _ ->
                                BackendTask.succeed result

                            EffectExit _ ->
                                BackendTask.succeed result
                    )
