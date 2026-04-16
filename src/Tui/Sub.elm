module Tui.Sub exposing
    ( Sub
    , none, batch, onKeyPress, onMouse, onPaste, onResize, everyMillis
    , map
    , KeyEvent, Key(..), Direction(..), Modifier(..)
    , MouseEvent(..), MouseButton(..)
    , RawEvent(..)
    , decodeRawEvent, getInterests, getTickIntervals, routeEvents
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


## Internal

Low-level framework hooks for companion packages (`tui-widgets`,
`Tui.Test`) and test tooling. **Not stable.** Regular TUI apps do not need
these — use the smart constructors above.

@docs RawEvent
@docs decodeRawEvent, getInterests, getTickIntervals, routeEvents

-}

import Json.Decode as Decode
import Json.Encode as Encode
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



-- SUB (opaque — constructors are private to this module)


{-| A TUI subscription.
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



-- RAW EVENTS AND ROUTING (framework-internal)


{-| A raw terminal event before it's routed through a subscription. Exposed
for framework use (running the TUI loop, simulating events in tests).
-}
type RawEvent
    = RawKeyPress KeyEvent
    | RawMouse MouseEvent
    | RawPaste String
    | RawResize
    | RawContext { width : Int, height : Int }
    | RawTick { interval : Int, time : Posix }


{-| Collect the event-type interests declared by a `Sub`, as a JSON value
the TUI runtime can use to decide which terminal event sources to enable
(mouse tracking, paste mode, etc.).
-}
getInterests : Sub msg -> Encode.Value
getInterests sub =
    let
        collect : Sub msg -> List String -> List String
        collect s acc =
            -- elm-review: known-unoptimized-recursion
            case s of
                SubNone ->
                    acc

                SubBatch subs ->
                    List.foldl (\inner a -> collect inner a) acc subs

                OnKeyPress _ ->
                    "keypress" :: acc

                OnMouse _ ->
                    "mouse" :: acc

                OnPaste _ ->
                    "paste" :: acc

                OnResize _ ->
                    acc

                Every _ _ ->
                    acc
    in
    collect sub []
        |> (\interests -> "resize" :: interests)
        |> List.reverse
        |> Encode.list Encode.string


{-| Collect unique tick intervals (in ms) across the subscription tree.
Duplicates are removed so the JS runtime only starts one timer per interval
even if multiple `everyMillis` subscriptions share it.
-}
getTickIntervals : Sub msg -> List Int
getTickIntervals sub =
    let
        collect : Sub msg -> List Int -> List Int
        collect s acc =
            -- elm-review: known-unoptimized-recursion
            case s of
                SubNone ->
                    acc

                SubBatch subs ->
                    List.foldl (\inner a -> collect inner a) acc subs

                Every interval _ ->
                    if List.member interval acc then
                        acc

                    else
                        interval :: acc

                _ ->
                    acc
    in
    collect sub []
        |> List.reverse


{-| Route a raw event to every matching subscription and return each resulting
message. Returns a list so batched subscriptions of the same kind (e.g., two
`everyMillis 1000` subs or two `onKeyPress` handlers) all fire on a single
event. Resize-without-dimensions events are never routed — they are handled
by the framework.
-}
routeEvents : Sub msg -> RawEvent -> List msg
routeEvents sub event =
    -- elm-review: known-unoptimized-recursion
    case sub of
        SubNone ->
            []

        SubBatch subs ->
            List.concatMap (\s -> routeEvents s event) subs

        OnKeyPress toMsg ->
            case event of
                RawKeyPress keyEvent ->
                    [ toMsg keyEvent ]

                _ ->
                    []

        OnMouse toMsg ->
            case event of
                RawMouse mouseEvent ->
                    [ toMsg mouseEvent ]

                _ ->
                    []

        OnPaste toMsg ->
            case event of
                RawPaste pastedText ->
                    [ toMsg pastedText ]

                _ ->
                    []

        OnResize toMsg ->
            case event of
                RawContext ctx ->
                    [ toMsg ctx ]

                _ ->
                    []

        Every subInterval toMsg ->
            case event of
                RawTick { interval, time } ->
                    if interval == subInterval then
                        [ toMsg time ]

                    else
                        []

                _ ->
                    []


{-| Decode a raw terminal event (as sent from the Node runtime) into a
`RawEvent`.
-}
decodeRawEvent : Decode.Decoder RawEvent
decodeRawEvent =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\eventType ->
                case eventType of
                    "keypress" ->
                        Decode.map RawKeyPress decodeKeyEvent

                    "mouse" ->
                        Decode.map RawMouse decodeMouseEvent

                    "paste" ->
                        Decode.map RawPaste
                            (Decode.field "text" Decode.string)

                    "resize" ->
                        Decode.succeed RawResize

                    "tick" ->
                        Decode.map2
                            (\interval time ->
                                RawTick { interval = interval, time = Time.millisToPosix time }
                            )
                            (Decode.field "interval" Decode.int)
                            (Decode.field "time" Decode.int)

                    _ ->
                        Decode.fail ("Unknown event type: " ++ eventType)
            )


decodeKeyEvent : Decode.Decoder KeyEvent
decodeKeyEvent =
    Decode.map2 KeyEvent
        (Decode.field "key" decodeKey)
        (Decode.field "modifiers" (Decode.list decodeModifier))


decodeKey : Decode.Decoder Key
decodeKey =
    Decode.field "tag" Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "Character" ->
                        Decode.field "char" Decode.string
                            |> Decode.andThen
                                (\s ->
                                    case String.uncons s of
                                        Just ( c, _ ) ->
                                            Decode.succeed (Character c)

                                        Nothing ->
                                            Decode.fail "Empty character"
                                )

                    "Enter" ->
                        Decode.succeed Enter

                    "Escape" ->
                        Decode.succeed Escape

                    "Tab" ->
                        Decode.succeed Tab

                    "Backspace" ->
                        Decode.succeed Backspace

                    "Delete" ->
                        Decode.succeed Delete

                    "Home" ->
                        Decode.succeed Home

                    "End" ->
                        Decode.succeed End

                    "PageUp" ->
                        Decode.succeed PageUp

                    "PageDown" ->
                        Decode.succeed PageDown

                    "Arrow" ->
                        Decode.field "direction" Decode.string
                            |> Decode.andThen
                                (\dir ->
                                    case dir of
                                        "Up" ->
                                            Decode.succeed (Arrow Up)

                                        "Down" ->
                                            Decode.succeed (Arrow Down)

                                        "Left" ->
                                            Decode.succeed (Arrow Left)

                                        "Right" ->
                                            Decode.succeed (Arrow Right)

                                        _ ->
                                            Decode.fail ("Unknown direction: " ++ dir)
                                )

                    "FunctionKey" ->
                        Decode.field "number" Decode.int
                            |> Decode.map FunctionKey

                    _ ->
                        Decode.fail ("Unknown key tag: " ++ tag)
            )


decodeModifier : Decode.Decoder Modifier
decodeModifier =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "Ctrl" ->
                        Decode.succeed Ctrl

                    "Alt" ->
                        Decode.succeed Alt

                    "Shift" ->
                        Decode.succeed Shift

                    _ ->
                        Decode.fail ("Unknown modifier: " ++ s)
            )


decodeMouseEvent : Decode.Decoder MouseEvent
decodeMouseEvent =
    Decode.field "action" Decode.string
        |> Decode.andThen
            (\action ->
                let
                    coords : Decode.Decoder { row : Int, col : Int }
                    coords =
                        Decode.map2 (\r c -> { row = r, col = c })
                            (Decode.field "row" Decode.int)
                            (Decode.field "col" Decode.int)
                in
                case action of
                    "click" ->
                        Decode.map2
                            (\pos button ->
                                Click { row = pos.row, col = pos.col, button = button }
                            )
                            coords
                            (Decode.field "button" decodeMouseButton)

                    "scrollUp" ->
                        Decode.map2
                            (\pos amt -> ScrollUp { row = pos.row, col = pos.col, amount = amt })
                            coords
                            (Decode.field "amount" Decode.int
                                |> Decode.maybe
                                |> Decode.map (Maybe.withDefault 1)
                            )

                    "scrollDown" ->
                        Decode.map2
                            (\pos amt -> ScrollDown { row = pos.row, col = pos.col, amount = amt })
                            coords
                            (Decode.field "amount" Decode.int
                                |> Decode.maybe
                                |> Decode.map (Maybe.withDefault 1)
                            )

                    _ ->
                        Decode.fail ("Unknown mouse action: " ++ action)
            )


decodeMouseButton : Decode.Decoder MouseButton
decodeMouseButton =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "left" ->
                        Decode.succeed LeftButton

                    "middle" ->
                        Decode.succeed MiddleButton

                    "right" ->
                        Decode.succeed RightButton

                    _ ->
                        Decode.fail ("Unknown mouse button: " ++ s)
            )
