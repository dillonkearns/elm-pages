module Tui.Sub.Internal exposing
    ( Sub(..)
    , RawEvent(..)
    , getInterests, getTickIntervals, routeEvents
    , decodeRawEvent
    )

{-| Internal machinery for `Tui.Sub`. Not exposed from the package.

The `Sub` type constructors live here so that other non-exposed modules
(`Tui.Internal`, `Tui.Test`) can pattern-match on subscriptions to
inspect interests, derive tick intervals, and route raw terminal events
into user messages without leaking these internals through `Tui.Sub`.

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Time exposing (Posix)
import Tui exposing (KeyEvent, MouseEvent)


type Sub msg
    = SubNone
    | SubBatch (List (Sub msg))
    | OnKeyPress (KeyEvent -> msg)
    | OnMouse (MouseEvent -> msg)
    | OnPaste (String -> msg)
    | OnContext ({ width : Int, height : Int } -> msg)
    | Every Int (Posix -> msg)


type RawEvent
    = RawKeyPress KeyEvent
    | RawMouse MouseEvent
    | RawPaste String
    | RawResize { width : Int, height : Int }
    | RawContext { width : Int, height : Int }
    | RawTick { interval : Int, time : Posix }


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

                OnContext _ ->
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
even if multiple `Every` subscriptions share it.
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
`Every 1000` subs or two `onKeyPress` handlers) all fire on a single event.
Resize events are never routed — they are handled by the framework.
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

        OnContext toMsg ->
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
                        Decode.map RawResize
                            (Decode.map2 (\w h -> { width = w, height = h })
                                (Decode.field "width" Decode.int)
                                (Decode.field "height" Decode.int)
                            )

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
