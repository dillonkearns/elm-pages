module Tui.Layout.Effect exposing
    ( Effect(..)
    , none, batch, perform, attempt, exit, exitWithCode
    , Toast, info, error, toast
    , focusPane, resetScroll, scrollTo, scrollDown, scrollUp, setSelectedIndex, selectFirst
    , map
    )

{-| Effects for apps built with [`Layout.compileApp`](Tui-Layout#compileApp).

Wraps core [`Tui.Effect`](Tui-Effect) effects and adds layout-specific
operations like focus and scroll control. Import this instead of `Tui.Effect`
when using `compileApp`:

    import Tui.Layout.Effect as Effect

    update : UpdateContext -> Msg -> Model -> ( Model, Effect Msg )
    update ctx msg model =
        case msg of
            SelectCommit idx ->
                ( model
                , Effect.batch
                    [ loadDiff idx |> Effect.perform GotDiff
                    , Effect.focusPane "diff"
                    , Effect.toast (Effect.info "Loading...")
                    ]
                )


## Core Effects

@docs Effect
@docs none, batch, perform, attempt, exit, exitWithCode


## Toast

@docs Toast, info, error, toast


## Layout Operations

@docs focusPane, resetScroll, scrollTo, scrollDown, scrollUp, setSelectedIndex, selectFirst


## Transform

@docs map

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Tui.Effect as CoreEffect


{-| An effect produced by `update` or `init` in a `compileApp` app.

Includes both core effects (BackendTask, exit, toast) and layout-specific
operations (focus, scroll, selection).

-}
type Effect msg
    = CoreEffect (CoreEffect.Effect msg)
    | Batch (List (Effect msg))
    | FocusPane String
    | ResetScroll String
    | ScrollTo String Int
    | ScrollDown String Int
    | ScrollUp String Int
    | SetSelectedIndex String Int
    | SelectFirst String


{-| No effect.
-}
none : Effect msg
none =
    CoreEffect CoreEffect.none


{-| Combine multiple effects.
-}
batch : List (Effect msg) -> Effect msg
batch =
    Batch


{-| Run a `BackendTask` and deliver the result as a message.

    Script.exec "git" [ "add", file ]
        |> Effect.perform (\() -> StagingComplete)

-}
perform : (a -> msg) -> BackendTask FatalError a -> Effect msg
perform toMsg bt =
    CoreEffect (CoreEffect.perform toMsg bt)


{-| Run a `BackendTask` that may fail, delivering `Ok` or `Err` as a message.
-}
attempt : (Result FatalError a -> msg) -> BackendTask FatalError a -> Effect msg
attempt toMsg bt =
    CoreEffect (CoreEffect.attempt toMsg bt)


{-| Exit the TUI with code 0.
-}
exit : Effect msg
exit =
    CoreEffect CoreEffect.exit


{-| Exit the TUI with a specific exit code.
-}
exitWithCode : Int -> Effect msg
exitWithCode code =
    CoreEffect (CoreEffect.exitWithCode code)


{-| Opaque toast configuration. Build with [`info`](#info) or [`error`](#error).
-}
type alias Toast =
    CoreEffect.Toast


{-| Create an informational toast.

    Effect.toast (Effect.info "Saved!")

-}
info : String -> Toast
info =
    CoreEffect.info


{-| Create an error toast.

    Effect.toast (Effect.error "Failed to save")

-}
error : String -> Toast
error =
    CoreEffect.error


{-| Show a toast notification. Fire and forget.

    Effect.toast (Effect.info "Saved!")
    Effect.toast (Effect.error "Connection lost")

-}
toast : Toast -> Effect msg
toast t =
    CoreEffect (CoreEffect.toast t)


{-| Move keyboard focus to a specific pane.

    Effect.focusPane "commits"

-}
focusPane : String -> Effect msg
focusPane =
    FocusPane


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


{-| Transform the message type of an effect.
-}
map : (a -> b) -> Effect a -> Effect b
map f effect =
    -- elm-review: known-unoptimized-recursion
    case effect of
        CoreEffect core ->
            CoreEffect (CoreEffect.map f core)

        Batch effects ->
            Batch (List.map (map f) effects)

        FocusPane paneId ->
            FocusPane paneId

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
