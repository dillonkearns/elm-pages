module Tui.Sub exposing
    ( Sub
    , none, batch, onKeyPress, onResize, every
    , map
    , getInterests, routeEvent
    , RawEvent(..), decodeRawEvent
    )

{-| Subscriptions for TUI terminal events. Unlike `Platform.Sub`, these are
inspectable — the framework and test harness can see what events are subscribed
to and route them accordingly.

    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.batch
            [ Sub.onKeyPress KeyPressed
            , Sub.onResize Resized
            ]

@docs Sub

@docs none, batch, onKeyPress, onResize, every

@docs map

@docs getInterests, routeEvent

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Tui exposing (KeyEvent)


{-| A TUI subscription — declares which terminal events to listen for.
-}
type Sub msg
    = SubNone
    | SubBatch (List (Sub msg))
    | OnKeyPress (KeyEvent -> msg)
    | OnResize ({ width : Int, height : Int } -> msg)
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


{-| Subscribe to terminal resize events.
-}
onResize : ({ width : Int, height : Int } -> msg) -> Sub msg
onResize =
    OnResize


{-| Periodic tick. The `Float` is the interval in milliseconds.
-}
every : Float -> msg -> Sub msg
every =
    Every


{-| Transform the message type of a subscription.
-}
map : (a -> b) -> Sub a -> Sub b
map f sub =
    case sub of
        SubNone ->
            SubNone

        SubBatch subs ->
            SubBatch (List.map (map f) subs)

        OnKeyPress toMsg ->
            OnKeyPress (\event -> f (toMsg event))

        OnResize toMsg ->
            OnResize (\size -> f (toMsg size))

        Every interval msg ->
            Every interval (f msg)



-- INTERNAL: Interests and routing


{-| Extract the set of event types this subscription is interested in.
Encoded as JSON for the JS runtime.
-}
getInterests : Sub msg -> Encode.Value
getInterests sub =
    let
        collect : Sub msg -> List String -> List String
        collect s acc =
            case s of
                SubNone ->
                    acc

                SubBatch subs ->
                    List.foldl (\inner a -> collect inner a) acc subs

                OnKeyPress _ ->
                    "keypress" :: acc

                OnResize _ ->
                    "resize" :: acc

                Every _ _ ->
                    "tick" :: acc
    in
    collect sub []
        |> List.reverse
        |> Encode.list Encode.string


{-| Route a raw event through a subscription to produce a user message.
Returns Nothing if the event doesn't match any subscription.
-}
routeEvent : Sub msg -> RawEvent -> Maybe msg
routeEvent sub event =
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

        OnResize toMsg ->
            case event of
                RawResize size ->
                    Just (toMsg size)

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
    | RawResize { width : Int, height : Int }
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
