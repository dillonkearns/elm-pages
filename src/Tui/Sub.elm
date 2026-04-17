module Tui.Sub exposing
    ( Sub(..)
    , none, batch, onKeyPress, onMouse, onPaste, onResize, everyMillis
    , map
    , KeyEvent, Key(..), Direction(..), Modifier(..)
    , MouseEvent(..), MouseButton(..)
    )

{-| Subscriptions for a [`Tui.Program`](Tui#Program).

    import Tui.Sub

    type Msg
        = KeyPressed Tui.Sub.KeyEvent
        | Resized { width : Int, height : Int }

    subscriptions : Model -> Tui.Sub.Sub Msg
    subscriptions _ =
        Tui.Sub.batch
            [ Tui.Sub.onKeyPress KeyPressed
            , Tui.Sub.onResize Resized
            ]

    update : Msg -> Model -> ( Model, Effect.Effect Msg )
    update msg model =
        case msg of
            KeyPressed event ->
                case event.key of
                    Tui.Sub.Character 'q' ->
                        ( model, Effect.exit )

                    Tui.Sub.Arrow Tui.Sub.Up ->
                        ( { model | count = model.count + 1 }
                        , Effect.none
                        )

                    _ ->
                        ( model, Effect.none )

            Resized _ ->
                ( model, Effect.none )

@docs Sub


## Subscribing

@docs none, batch, onKeyPress, onMouse, onPaste, onResize, everyMillis


## Transforming

@docs map


## Keyboard events

The values you pattern-match on inside `update` when handling
[`onKeyPress`](#onKeyPress).

@docs KeyEvent, Key, Direction, Modifier


## Mouse events

The values you pattern-match on inside `update` when handling
[`onMouse`](#onMouse).

@docs MouseEvent, MouseButton

-}

import Time exposing (Posix)



-- KEYBOARD


{-| A keyboard event from the terminal.
-}
type alias KeyEvent =
    { key : Key
    , modifiers : List Modifier
    }


{-| Key values.
-}
type Key
    = Character Char
    | Enter
    | Escape
    | Tab
    | Backspace
    | Delete
    | Arrow Direction
    | FunctionKey Int
    | Home
    | End
    | PageUp
    | PageDown


{-| Arrow key direction.
-}
type Direction
    = Up
    | Down
    | Left
    | Right


{-| Key modifier.
-}
type Modifier
    = Ctrl
    | Alt
    | Shift



-- MOUSE


{-| Mouse event from the terminal. Uses SGR extended mouse mode for accurate
coordinates on any terminal size.

Coordinates are 0-based: `{ row = 0, col = 0 }` is the top-left corner.

`amount` on scroll events is the number of coalesced scroll steps. Rapid
scrolling batches events on the JS side (like gocui's event drain) so you
get one event with `amount = 5` instead of 5 separate events. Multiply your
scroll distance by `amount` for responsive feel.

-}
type MouseEvent
    = Click { row : Int, col : Int, button : MouseButton }
    | ScrollUp { row : Int, col : Int, amount : Int }
    | ScrollDown { row : Int, col : Int, amount : Int }


{-| Mouse button for click events.
-}
type MouseButton
    = LeftButton
    | MiddleButton
    | RightButton



-- SUB


{-| A TUI subscription. Build values with [`none`](#none), [`batch`](#batch),
[`onKeyPress`](#onKeyPress), [`onMouse`](#onMouse), [`onPaste`](#onPaste),
[`onResize`](#onResize), and [`everyMillis`](#everyMillis). The constructors
are implementation details; application code should not pattern-match on them.
-}
type Sub msg
    = SubNone
    | SubBatch (List (Sub msg))
    | OnKeyPress (KeyEvent -> msg)
    | OnMouse (MouseEvent -> msg)
    | OnPaste (String -> msg)
    | OnResize ({ width : Int, height : Int } -> msg)
    | Every Int (Posix -> msg)


{-| No subscriptions.
-}
none : Sub msg
none =
    SubNone


{-| Combine multiple subscriptions.
-}
batch : List (Sub msg) -> Sub msg
batch =
    SubBatch


{-| Subscribe to [keyboard events](#keyboard-events).
-}
onKeyPress : (KeyEvent -> msg) -> Sub msg
onKeyPress =
    OnKeyPress


{-| Subscribe to mouse events (click, scroll). Enables SGR extended mouse
reporting in the terminal when subscribed.
-}
onMouse : (MouseEvent -> msg) -> Sub msg
onMouse =
    OnMouse


{-| Subscribe to paste events. You can receive paste events and
choose how to handle it in your program (treating it as normal text,
or as you sometimes see in TUIs, bracketed text).
-}
onPaste : (String -> msg) -> Sub msg
onPaste =
    OnPaste


{-| Subscribe to terminal resize events. Fires once on init with the starting
terminal dimensions, and again whenever the terminal is resized. The record
contains `width` and `height` in columns/rows.

Use this to store dimensions in your model (e.g., for `Layout.withContext`
or `Layout.handleMouse`).

    Tui.Sub.onResize (\{ width, height } -> Resized width height)

-}
onResize : ({ width : Int, height : Int } -> msg) -> Sub msg
onResize =
    OnResize


{-| Periodic tick at the given interval in milliseconds. The message
constructor receives the wall-clock time ([`Time.Posix`](https://package.elm-lang.org/packages/elm/time/latest/Time#Posix)) at which the tick
actually fired. You can store it in your `Model` and subtract from the previous tick
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

Each unique interval runs independently. When the runtime is blocked
for longer than the interval, catch-up fires once with the actual elapsed
`Posix` (it does not rapid-fire the missed ticks).

-}
everyMillis : Int -> (Posix -> msg) -> Sub msg
everyMillis =
    Every


{-| Transform the message type of a subscription.
-}
map : (a -> b) -> Sub a -> Sub b
map f sub =
    -- elm-review: known-unoptimized-recursion
    case sub of
        SubNone ->
            SubNone

        SubBatch subs ->
            SubBatch (List.map (map f) subs)

        OnKeyPress toMsg ->
            OnKeyPress (\event -> f (toMsg event))

        OnMouse toMsg ->
            OnMouse (\event -> f (toMsg event))

        OnPaste toMsg ->
            OnPaste (\text -> f (toMsg text))

        OnResize toMsg ->
            OnResize (\ctx -> f (toMsg ctx))

        Every interval toMsg ->
            Every interval (\time -> f (toMsg time))
