module Tui.Sub.Internal exposing
    ( RawEvent(..)
    , getInterests, getTickIntervals, routeEvents
    , decodeRawEvent
    )

{-| Framework-internal hooks for `Tui.Sub`. Not part of the public API.

These are used by the TUI runtime (`Tui`) and the test harness (`Test.Tui`)
to declare event-source interests, collect tick intervals, and route raw
terminal events to user subscriptions. Application code and framework
consumers (like `tui-widgets`) should not import this module.

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Time exposing (Posix)
import Tui.Sub exposing (Direction(..), Key(..), KeyEvent, Modifier(..), MouseButton(..), MouseEvent(..), Sub(..))


{-| A raw terminal event before it's routed through a subscription.
-}
type RawEvent
    = RawKeyPress KeyEvent
    | RawMouse MouseEvent
    | RawPaste String
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
event. Context updates should be routed through `RawContext`.
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


decodeRawEvent : Decode.Decoder (Maybe RawEvent)
decodeRawEvent =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\eventType ->
                case eventType of
                    "keypress" ->
                        Decode.map (Just << RawKeyPress) decodeKeyEvent

                    "mouse" ->
                        Decode.map (Just << RawMouse) decodeMouseEvent

                    "paste" ->
                        Decode.map (Just << RawPaste)
                            (Decode.field "text" Decode.string)

                    "resize" ->
                        Decode.succeed Nothing

                    "tick" ->
                        Decode.map2
                            (\interval time ->
                                Just (RawTick { interval = interval, time = Time.millisToPosix time })
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
