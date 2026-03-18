module Tui.Toast exposing
    ( State, init, toast, errorToast
    , tick, view
    , hasToasts
    )

{-| Auto-dismissing toast notifications for TUI applications.

Inspired by lazygit's status manager: normal toasts show for 2 seconds
in cyan, error toasts show for 4 seconds in red. Stack-based: newest
toast wins (displayed on top). Uses `Tui.Sub.every` for auto-dismiss.

    -- Model
    type alias Model =
        { toasts : Toast.State Msg
        , ...
        }

    -- Show a toast
    Toast.toast "Committed: fix parser" model.toasts

    -- In subscriptions (only while toasts are active)
    if Toast.hasToasts model.toasts then
        Tui.Sub.every 100 ToastTick
    else
        Tui.Sub.none

    -- In update
    ToastTick ->
        ( { model | toasts = Toast.tick model.toasts }, Effect.none )

    -- In view (render at the bottom or wherever you want)
    Toast.view model.toasts

@docs State, init, toast, errorToast
@docs tick, view
@docs hasToasts

-}

import Ansi.Color
import Tui


{-| Opaque toast state. Stores a stack of active toasts with their
remaining tick counts.
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


{-| Show a normal toast (cyan, ~2 seconds = 20 ticks at 100ms).
-}
toast : String -> State -> State
toast message (State items) =
    State ({ message = message, severity = Normal, ticksRemaining = 20 } :: items)


{-| Show an error toast (red, ~4 seconds = 40 ticks at 100ms).
-}
errorToast : String -> State -> State
errorToast message (State items) =
    State ({ message = message, severity = Error, ticksRemaining = 40 } :: items)


{-| Advance the timer. Call this from your update when `ToastTick` fires.
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


{-| Are there any active toasts? Use this to conditionally subscribe
to the tick timer.

    if Toast.hasToasts model.toasts then
        Tui.Sub.every 100 ToastTick
    else
        Tui.Sub.none

-}
hasToasts : State -> Bool
hasToasts (State items) =
    not (List.isEmpty items)


{-| Render the most recent toast. Returns `Tui.empty` when no toasts
are active. Normal toasts render in cyan, error toasts in red.
-}
view : State -> Tui.Screen
view (State items) =
    case items of
        [] ->
            Tui.empty

        item :: _ ->
            let
                color =
                    case item.severity of
                        Normal ->
                            Ansi.Color.cyan

                        Error ->
                            Ansi.Color.red
            in
            Tui.text (" " ++ item.message ++ " ") |> Tui.fg color
