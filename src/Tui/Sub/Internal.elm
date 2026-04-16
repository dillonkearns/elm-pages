module Tui.Sub.Internal exposing (decodeRawEvent)

import Json.Decode as Decode
import Time
import Tui.Sub exposing (Direction(..), Key(..), KeyEvent, Modifier(..), MouseButton(..), MouseEvent(..), RawEvent(..))


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
