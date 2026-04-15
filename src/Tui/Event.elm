module Tui.Event exposing
    ( KeyEvent, Key(..), Direction(..), Modifier(..)
    , MouseEvent(..), MouseButton(..)
    )

{-| Terminal input event types — keys and mouse. These arrive through
[`Tui.Sub.onKeyPress`](Tui-Sub#onKeyPress) and
[`Tui.Sub.onMouse`](Tui-Sub#onMouse) and are what you pattern-match on
in `update`.

    update : Msg -> Model -> ( Model, Effect.Effect Msg )
    update msg model =
        case msg of
            KeyPressed event ->
                case event.key of
                    Tui.Event.Character 'q' ->
                        ( model, Effect.exit )

                    Tui.Event.Arrow Tui.Event.Up ->
                        ( { model | count = model.count + 1 }, Effect.none )

                    _ ->
                        ( model, Effect.none )


## Keyboard

@docs KeyEvent, Key, Direction, Modifier


## Mouse

@docs MouseEvent, MouseButton

-}


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
