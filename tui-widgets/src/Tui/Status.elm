module Tui.Status exposing
    ( State, init
    , toast, errorToast
    , tick
    , view, hasActivity
    )

{-| Unified status system for TUI applications — toasts, waiting indicators,
and spinners in one module.

This is the recommended way to show ephemeral feedback. It combines
[`Tui.Toast`](Tui-Toast) auto-dismiss behavior with [`Tui.Spinner`](Tui-Spinner)
animations for in-flight operations. When using [`Layout.compileApp`](Tui-Layout#compileApp),
status is managed automatically via the `status` callback.

Toasts are ephemeral messages that auto-dismiss. Waiting status shows a
spinner for in-flight operations. The waiting message is passed declaratively
to `view` — your model tracks whether an operation is in flight, and Status
just renders it.

    -- Model
    type alias Model =
        { status : Status.State
        , spinnerTick : Int
        , pushing : Maybe String  -- Nothing when idle, Just "Pushing..." when active
        }

    -- Show a toast after an operation completes
    PushComplete ->
        ( { model
            | pushing = Nothing
            , status = Status.toast "Pushed!" model.status
          }
        , Effect.none
        )

    -- In subscriptions (only while active)
    if Status.hasActivity model.status { waiting = model.pushing } then
        Tui.Sub.everyMillis 100 (\_ -> Tick)
    else
        Tui.Sub.none

    -- In update
    Tick ->
        ( { model | spinnerTick = model.spinnerTick + 1, status = Status.tick model.status }
        , Effect.none
        )

    -- In view (renders at the bottom)
    Status.view { waiting = model.pushing, tick = model.spinnerTick } model.status

@docs State, init

@docs toast, errorToast

@docs tick

@docs view, hasActivity

-}

import Ansi.Color
import Tui
import Tui.Screen


{-| Opaque status state. Manages the toast queue and tick counts.
Waiting state is NOT stored here — it's passed declaratively to `view`.
-}
type State
    = State (List ToastItem)


type alias ToastItem =
    { message : String
    , severity : Severity
    , ticksRemaining : Int
    }


type Severity
    = Normal
    | Error


{-| Initialize with no toasts.
-}
init : State
init =
    State []


{-| Show a normal toast (cyan). Lasts 20 ticks — with the recommended
`Tui.Sub.everyMillis 100` interval, that's ~2 seconds.
-}
toast : String -> State -> State
toast message (State items) =
    State ({ message = message, severity = Normal, ticksRemaining = 20 } :: items)


{-| Show an error toast (red). Lasts 40 ticks — with the recommended
`Tui.Sub.everyMillis 100` interval, that's ~4 seconds.
-}
errorToast : String -> State -> State
errorToast message (State items) =
    State ({ message = message, severity = Error, ticksRemaining = 40 } :: items)


{-| Advance the timer. Call this from your update when the tick fires.
Removes toasts whose time has expired.
-}
tick : State -> State
tick (State items) =
    items
        |> List.filterMap
            (\item ->
                if item.ticksRemaining <= 1 then
                    Nothing

                else
                    Just { item | ticksRemaining = item.ticksRemaining - 1 }
            )
        |> State


{-| Render the current status. Always returns a `Tui.Screen.Screen` — renders
`Tui.Screen.empty` when nothing is active (no need to wrap in `Maybe`).

  - **Waiting** takes priority: shows the message with an animated spinner
  - **Toast** shows the most recent toast (cyan for normal, red for error)
  - **Nothing active**: returns `Tui.Screen.empty` (renders nothing)

The waiting message comes from YOUR model — Status doesn't track it.
This keeps the "am I doing something?" state explicit in your model,
where it belongs.

    -- Just place it in your view — no case/Maybe needed:
    Status.view { waiting = model.activeOperation, tick = model.spinnerTick } model.status

-}
view : { waiting : Maybe String, tick : Int } -> State -> Tui.Screen.Screen
view config (State items) =
    case config.waiting of
        Just message ->
            -- Waiting status with spinner
            let
                spinnerFrames =
                    [ "|", "/", "-", "\\" ]

                frame =
                    spinnerFrames
                        |> List.drop (modBy 4 config.tick)
                        |> List.head
                        |> Maybe.withDefault "|"
            in
            Tui.Screen.concat
                [ Tui.Screen.text (" " ++ message ++ " ")
                    |> Tui.Screen.fg Ansi.Color.cyan
                , Tui.Screen.text frame
                    |> Tui.Screen.fg Ansi.Color.cyan
                ]

        Nothing ->
            -- Show most recent toast
            case items of
                [] ->
                    Tui.Screen.empty

                item :: _ ->
                    let
                        color =
                            case item.severity of
                                Normal ->
                                    Ansi.Color.cyan

                                Error ->
                                    Ansi.Color.red
                    in
                    Tui.Screen.text (" " ++ item.message ++ " ") |> Tui.Screen.fg color


{-| Is there any active status (toasts or waiting)? Use this to
conditionally subscribe to the tick timer.

    if Status.hasActivity model.status { waiting = model.pushing } then
        Tui.Sub.everyMillis 100 (\_ -> Tick)
    else
        Tui.Sub.none

-}
hasActivity : { waiting : Maybe String } -> State -> Bool
hasActivity config (State items) =
    config.waiting /= Nothing || not (List.isEmpty items)
