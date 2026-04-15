module Tui.Sub exposing
    ( Sub
    , none, batch, onKeyPress, onMouse, onPaste, onContext, everyMillis
    , map
    )

{-| Subscriptions for TUI terminal events. Unlike `Platform.Sub`, these are
inspectable — the framework and test harness can see what events are subscribed
to and route them accordingly.

Terminal resize is handled automatically by the framework — `view` always
receives the current terminal dimensions via `Tui.Context`. You do not need
to subscribe to resize events.

    subscriptions : Model -> Tui.Sub Msg
    subscriptions _ =
        Tui.Sub.onKeyPress KeyPressed

@docs Sub

@docs none, batch, onKeyPress, onMouse, onPaste, onContext, everyMillis

@docs map

-}

import Time exposing (Posix)
import Tui.Event exposing (KeyEvent, MouseEvent)
import Tui.Sub.Internal as Internal


{-| A TUI subscription — declares which terminal events to listen for.
-}
type alias Sub msg =
    Internal.Sub msg


{-| No subscriptions.
-}
none : Sub msg
none =
    Internal.SubNone


{-| Combine multiple subscriptions.
-}
batch : List (Sub msg) -> Sub msg
batch =
    Internal.SubBatch


{-| Subscribe to keyboard events.
-}
onKeyPress : (KeyEvent -> msg) -> Sub msg
onKeyPress =
    Internal.OnKeyPress


{-| Subscribe to mouse events (click, scroll). Enables SGR extended mouse
reporting in the terminal when subscribed.
-}
onMouse : (MouseEvent -> msg) -> Sub msg
onMouse =
    Internal.OnMouse


{-| Subscribe to paste events. When the terminal has bracketed paste mode
enabled, pasted text arrives as a single event rather than individual
keypresses. Essential for text inputs — without this, pasting multi-line
text triggers keybindings for each character.

    Tui.Sub.onPaste GotPaste

-}
onPaste : (String -> msg) -> Sub msg
onPaste =
    Internal.OnPaste


{-| Subscribe to terminal dimension changes. Fires on init with the
initial terminal size, and whenever the terminal is resized. The record
contains `width` and `height` in columns/rows.

Use this to store dimensions in your model (e.g., for `Layout.withContext`
or `Layout.handleMouse`).

    Tui.Sub.onContext (\{ width, height } -> GotContext width height)

-}
onContext : ({ width : Int, height : Int } -> msg) -> Sub msg
onContext =
    Internal.OnContext


{-| Periodic tick at the given interval in milliseconds. The message
constructor receives the wall-clock time (`Time.Posix`) at which the tick
actually fired — store it in your model and subtract from the previous tick
to compute smooth deltas for animations.

    import Time

    type Msg
        = SpinnerTick Time.Posix
        | ClockTick Time.Posix

    subscriptions _ =
        Tui.Sub.batch
            [ Tui.Sub.everyMillis 50 SpinnerTick
            , Tui.Sub.everyMillis 1000 ClockTick
            ]

Each subscribed interval runs independently — batching two `everyMillis`
subs at different rates does not collapse them. Multiple subs at the same
interval all fire on each tick. When the runtime is blocked for longer than
the interval, catch-up fires once with the actual elapsed `Posix` — it does
not rapid-fire the missed ticks.

-}
everyMillis : Int -> (Posix -> msg) -> Sub msg
everyMillis =
    Internal.Every


{-| Transform the message type of a subscription.
-}
map : (a -> b) -> Sub a -> Sub b
map f sub =
    -- elm-review: known-unoptimized-recursion
    case sub of
        Internal.SubNone ->
            Internal.SubNone

        Internal.SubBatch subs ->
            Internal.SubBatch (List.map (map f) subs)

        Internal.OnKeyPress toMsg ->
            Internal.OnKeyPress (\event -> f (toMsg event))

        Internal.OnMouse toMsg ->
            Internal.OnMouse (\event -> f (toMsg event))

        Internal.OnPaste toMsg ->
            Internal.OnPaste (\text -> f (toMsg text))

        Internal.OnContext toMsg ->
            Internal.OnContext (\ctx -> f (toMsg ctx))

        Internal.Every interval toMsg ->
            Internal.Every interval (\time -> f (toMsg time))
