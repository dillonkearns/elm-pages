module Tui.Sub exposing
    ( Sub
    , none, batch, onKeyPress, onMouse, onContext, every
    , map
    , getInterests, routeEvent
    , RawEvent(..), decodeRawEvent
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

@docs none, batch, onKeyPress, onMouse, onContext, every

@docs map

@docs getInterests, routeEvent


## Internal

@docs RawEvent, decodeRawEvent

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Tui exposing (KeyEvent, MouseEvent)


{-| A TUI subscription — declares which terminal events to listen for.
-}
type Sub msg
    = SubNone
    | SubBatch (List (Sub msg))
    | OnKeyPress (KeyEvent -> msg)
    | OnMouse (MouseEvent -> msg)
    | OnContext ({ width : Int, height : Int } -> msg)
    | Every Float msg


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


{-| Subscribe to keyboard events.
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


{-| Subscribe to terminal context (dimension) changes. Fires on init with the
initial terminal size, and whenever the terminal is resized.

    Tui.Sub.onContext (\ctx -> GotContext ctx)

-}
onContext : ({ width : Int, height : Int } -> msg) -> Sub msg
onContext =
    OnContext


{-| Periodic tick. The `Float` is the interval in milliseconds.
-}
every : Float -> msg -> Sub msg
every =
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

        OnContext toMsg ->
            OnContext (\ctx -> f (toMsg ctx))

        Every interval msg ->
            Every interval (f msg)



-- INTERNAL: Interests and routing


{-| Extract the set of event types this subscription is interested in.
Encoded as JSON for the JS runtime. Resize is always included — the framework
handles it automatically.
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

                OnContext _ ->
                    -- Context events are framework-generated, not from stdin
                    acc

                Every _ _ ->
                    "tick" :: acc
    in
    collect sub []
        -- Always include resize so the framework can update Context
        |> (\interests -> "resize" :: interests)
        |> List.reverse
        |> Encode.list Encode.string


{-| Route a raw event through a subscription to produce a user message.
Returns Nothing if the event doesn't match any subscription.
Resize events are NOT routed to user code — they are handled by the framework.
-}
routeEvent : Sub msg -> RawEvent -> Maybe msg
routeEvent sub event =
    -- elm-review: known-unoptimized-recursion
    case sub of
        SubNone ->
            Nothing

        SubBatch subs ->
            subs
                |> List.filterMap (\s -> routeEvent s event)
                |> List.head

        OnKeyPress toMsg ->
            case event of
                RawKeyPress keyEvent ->
                    Just (toMsg keyEvent)

                _ ->
                    Nothing

        OnMouse toMsg ->
            case event of
                RawMouse mouseEvent ->
                    Just (toMsg mouseEvent)

                _ ->
                    Nothing

        OnContext toMsg ->
            case event of
                RawContext ctx ->
                    Just (toMsg ctx)

                _ ->
                    Nothing

        Every _ msg ->
            case event of
                RawTick ->
                    Just msg

                _ ->
                    Nothing


{-| Raw terminal event from JS.
-}
type RawEvent
    = RawKeyPress KeyEvent
    | RawMouse MouseEvent
    | RawResize { width : Int, height : Int }
    | RawContext { width : Int, height : Int }
    | RawTick


{-| Decode a raw event from JSON sent by the JS runtime.
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

                    "resize" ->
                        Decode.map RawResize
                            (Decode.map2 (\w h -> { width = w, height = h })
                                (Decode.field "width" Decode.int)
                                (Decode.field "height" Decode.int)
                            )

                    "tick" ->
                        Decode.succeed RawTick

                    _ ->
                        Decode.fail ("Unknown event type: " ++ eventType)
            )


decodeKeyEvent : Decode.Decoder KeyEvent
decodeKeyEvent =
    Decode.map2 Tui.KeyEvent
        (Decode.field "key" decodeKey)
        (Decode.field "modifiers" (Decode.list decodeModifier))


decodeKey : Decode.Decoder Tui.Key
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
                                            Decode.succeed (Tui.Character c)

                                        Nothing ->
                                            Decode.fail "Empty character"
                                )

                    "Enter" ->
                        Decode.succeed Tui.Enter

                    "Escape" ->
                        Decode.succeed Tui.Escape

                    "Tab" ->
                        Decode.succeed Tui.Tab

                    "Backspace" ->
                        Decode.succeed Tui.Backspace

                    "Delete" ->
                        Decode.succeed Tui.Delete

                    "Home" ->
                        Decode.succeed Tui.Home

                    "End" ->
                        Decode.succeed Tui.End

                    "PageUp" ->
                        Decode.succeed Tui.PageUp

                    "PageDown" ->
                        Decode.succeed Tui.PageDown

                    "Arrow" ->
                        Decode.field "direction" Decode.string
                            |> Decode.andThen
                                (\dir ->
                                    case dir of
                                        "Up" ->
                                            Decode.succeed (Tui.Arrow Tui.Up)

                                        "Down" ->
                                            Decode.succeed (Tui.Arrow Tui.Down)

                                        "Left" ->
                                            Decode.succeed (Tui.Arrow Tui.Left)

                                        "Right" ->
                                            Decode.succeed (Tui.Arrow Tui.Right)

                                        _ ->
                                            Decode.fail ("Unknown direction: " ++ dir)
                                )

                    "FunctionKey" ->
                        Decode.field "number" Decode.int
                            |> Decode.map Tui.FunctionKey

                    _ ->
                        Decode.fail ("Unknown key tag: " ++ tag)
            )


decodeModifier : Decode.Decoder Tui.Modifier
decodeModifier =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "Ctrl" ->
                        Decode.succeed Tui.Ctrl

                    "Alt" ->
                        Decode.succeed Tui.Alt

                    "Shift" ->
                        Decode.succeed Tui.Shift

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
                                Tui.Click { row = pos.row, col = pos.col, button = button }
                            )
                            coords
                            (Decode.field "button" decodeMouseButton)

                    "scrollUp" ->
                        Decode.map2
                            (\pos amt -> Tui.ScrollUp { row = pos.row, col = pos.col, amount = amt })
                            coords
                            (Decode.field "amount" Decode.int
                                |> Decode.maybe
                                |> Decode.map (Maybe.withDefault 1)
                            )

                    "scrollDown" ->
                        Decode.map2
                            (\pos amt -> Tui.ScrollDown { row = pos.row, col = pos.col, amount = amt })
                            coords
                            (Decode.field "amount" Decode.int
                                |> Decode.maybe
                                |> Decode.map (Maybe.withDefault 1)
                            )

                    _ ->
                        Decode.fail ("Unknown mouse action: " ++ action)
            )


decodeMouseButton : Decode.Decoder Tui.MouseButton
decodeMouseButton =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "left" ->
                        Decode.succeed Tui.LeftButton

                    "middle" ->
                        Decode.succeed Tui.MiddleButton

                    "right" ->
                        Decode.succeed Tui.RightButton

                    _ ->
                        Decode.fail ("Unknown mouse button: " ++ s)
            )
