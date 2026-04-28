module Tui.Layout.Effect exposing
    ( Effect
    , none, batch
    , perform, attempt
    , exit, exitWithCode
    , toast, errorToast
    , resetScroll, scrollTo, scrollDown, scrollUp
    , setSelectedIndex, selectFirst, focusPane
    , map
    )

{-| Effects for apps built with [`Tui.Layout.compileApp`](Tui-Layout#compileApp).

This is a superset of the core [`Tui.Effect`](Tui-Effect) type. It wraps the
runtime-level effects (`perform`, `attempt`, `exit`, …) and adds
framework-specific operations for scrolling, focus, selection, and toasts —
operations that only make sense when the `Layout.compileApp` framework is
managing state on your behalf.

    import Tui.Layout.Effect as Effect

    update : Layout.UpdateContext -> Msg -> Model -> ( Model, Effect.Effect Msg )
    update _ msg model =
        case msg of
            SelectCommit commit ->
                ( { model | activeOp = Just "Loading diff..." }
                , Effect.batch
                    [ Script.command "git" [ "show", commit.sha ]
                        |> Effect.attempt GotDiff
                    , Effect.resetScroll "diff"
                    ]
                )

If you are writing a plain TUI with [`Tui.program`](Tui#program) and not using
`Layout.compileApp`, use [`Tui.Effect`](Tui-Effect) directly — this module's
framework-specific effects have no meaning outside the Layout framework.

@docs Effect


## Basic effects

@docs none, batch

@docs perform, attempt

@docs exit, exitWithCode


## Status toasts

@docs toast, errorToast


## Scrolling

@docs resetScroll, scrollTo, scrollDown, scrollUp


## Selection and focus

@docs setSelectedIndex, selectFirst, focusPane


## Transforming

@docs map

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Tui.Effect
import Tui.Layout.Effect.Internal as Internal exposing (Effect(..))


{-| An effect produced by `update` or `init` in an app built with
`Layout.compileApp`.
-}
type alias Effect msg =
    Internal.Effect msg


{-| No effect.
-}
none : Effect msg
none =
    Runtime Tui.Effect.none


{-| Combine multiple effects.
-}
batch : List (Effect msg) -> Effect msg
batch =
    Batch


{-| Run a `BackendTask` and produce a message with the result. Errors
propagate as `FatalError` and crash the TUI with an error message. Use
[`attempt`](#attempt) when you want to handle errors as values.

    Script.command "git" [ "status", "--porcelain" ]
        |> BackendTask.map parseFiles
        |> Effect.perform GotFiles

-}
perform : (a -> msg) -> BackendTask FatalError a -> Effect msg
perform toMsg bt =
    Runtime (Tui.Effect.perform toMsg bt)


{-| Like [`perform`](#perform), but surfaces errors as `Result` values for
you to handle. Polymorphic in the error type — shape the error to something
meaningful for your code before passing it in.

    Script.command "git" [ "diff", file ]
        |> BackendTask.mapError (\_ -> "git diff failed")
        |> Effect.attempt GotDiff

-}
attempt : (Result error a -> msg) -> BackendTask error a -> Effect msg
attempt toMsg bt =
    Runtime (Tui.Effect.attempt toMsg bt)


{-| Exit the TUI (exit code 0). Terminal state is restored.
-}
exit : Effect msg
exit =
    Runtime Tui.Effect.exit


{-| Exit the TUI with a specific exit code. Terminal state is restored.
-}
exitWithCode : Int -> Effect msg
exitWithCode code =
    Runtime (Tui.Effect.exitWithCode code)


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


{-| Transform the message type of an effect.
-}
map : (a -> b) -> Effect a -> Effect b
map f effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        Runtime inner ->
            Runtime (Tui.Effect.map f inner)

        Batch effects ->
            Batch (List.map (map f) effects)

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
