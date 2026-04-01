module Tui.Effect.Internal exposing
    ( Effect(..)
    , none, batch, perform, attempt, exit, exitWithCode
    , toast, errorToast
    , resetScroll, scrollTo, scrollDown, scrollUp, setSelectedIndex, selectFirst, focusPane
    , map, fold
    , EffectResult(..), toBackendTask
    )

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)


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


none : Effect msg
none =
    None


batch : List (Effect msg) -> Effect msg
batch =
    Batch


perform : (a -> msg) -> BackendTask FatalError a -> Effect msg
perform toMsg bt =
    RunBackendTask (BackendTask.map toMsg bt)


attempt : (Result FatalError a -> msg) -> BackendTask FatalError a -> Effect msg
attempt toMsg bt =
    RunBackendTask
        (bt
            |> BackendTask.map (\a -> toMsg (Ok a))
            |> BackendTask.onError (\err -> BackendTask.succeed (toMsg (Err err)))
        )


exit : Effect msg
exit =
    Exit


exitWithCode : Int -> Effect msg
exitWithCode =
    ExitWithCode


toast : String -> Effect msg
toast =
    Toast


errorToast : String -> Effect msg
errorToast =
    ErrorToast


resetScroll : String -> Effect msg
resetScroll =
    ResetScroll


scrollTo : String -> Int -> Effect msg
scrollTo =
    ScrollTo


scrollDown : String -> Int -> Effect msg
scrollDown =
    ScrollDown


scrollUp : String -> Int -> Effect msg
scrollUp =
    ScrollUp


setSelectedIndex : String -> Int -> Effect msg
setSelectedIndex =
    SetSelectedIndex


selectFirst : String -> Effect msg
selectFirst =
    SelectFirst


focusPane : String -> Effect msg
focusPane =
    FocusPane


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
fold handlers effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        None ->
            handlers.none

        Batch effects ->
            handlers.batch effects

        RunBackendTask bt ->
            handlers.backendTask bt

        SuspendBackendTask bt ->
            handlers.backendTask bt

        Exit ->
            handlers.exit 0

        ExitWithCode code ->
            handlers.exit code

        Toast message ->
            handlers.toast message

        ErrorToast message ->
            handlers.errorToast message

        ResetScroll paneId ->
            handlers.resetScroll paneId

        ScrollTo paneId offset ->
            handlers.scrollTo paneId offset

        ScrollDown paneId amount ->
            handlers.scrollDown paneId amount

        ScrollUp paneId amount ->
            handlers.scrollUp paneId amount

        SetSelectedIndex paneId index ->
            handlers.setSelectedIndex paneId index

        SelectFirst paneId ->
            handlers.selectFirst paneId

        FocusPane paneId ->
            handlers.focusPane paneId


type EffectResult msg
    = EffectDone
    | EffectMsg msg
    | EffectExit Int


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
