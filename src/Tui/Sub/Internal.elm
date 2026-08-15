module Tui.Sub.Internal exposing
    ( RawEvent(..)
    , decodeRawEvent
    , getInterests
    , getTickIntervals
    , routeEvents
    )

{-| Framework-internal hooks for `Tui.Sub`. Not part of the public API.

These are used by the TUI runtime (`Tui`) and the test harness (`Test.Tui`)
to declare event-source interests, collect tick intervals, and route raw
terminal events to user subscriptions. Application code and framework
consumers (like `tui-widgets`) should not import this module.

-}

import Json.Encode as Encode
import Time exposing (Posix)
import TsJson.Decode as TsDecode
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
                    if interval <= 0 then
                        acc

                    else if List.member interval acc then
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
                    if subInterval > 0 && interval == subInterval then
                        [ toMsg time ]

                    else
                        []

                _ ->
                    []


decodeRawEvent : TsDecode.Decoder (Maybe RawEvent)
decodeRawEvent =
    TsDecode.discriminatedUnion "type"
        [ ( "keypress"
          , TsDecode.map (Just << RawKeyPress) decodeKeyEvent
          )
        , ( "mouse"
          , TsDecode.map (Just << RawMouse) decodeMouseEvent
          )
        , ( "paste"
          , TsDecode.map (Just << RawPaste)
                (TsDecode.field "text" TsDecode.string)
          )
        , ( "resize"
          , TsDecode.succeed Nothing
          )
        , ( "tick"
          , TsDecode.map2
                (\interval time ->
                    Just (RawTick { interval = interval, time = Time.millisToPosix time })
                )
                (TsDecode.field "interval" TsDecode.int)
                (TsDecode.field "time" TsDecode.int)
          )
        ]


decodeKeyEvent : TsDecode.Decoder KeyEvent
decodeKeyEvent =
    TsDecode.map2 KeyEvent
        (TsDecode.field "key" decodeKey)
        (TsDecode.field "modifiers" (TsDecode.list decodeModifier))


decodeKey : TsDecode.Decoder Key
decodeKey =
    TsDecode.discriminatedUnion "tag"
        [ ( "Character", TsDecode.field "char" charDecoder )
        , ( "Enter", TsDecode.succeed Enter )
        , ( "Escape", TsDecode.succeed Escape )
        , ( "Tab", TsDecode.succeed Tab )
        , ( "Backspace", TsDecode.succeed Backspace )
        , ( "Delete", TsDecode.succeed Delete )
        , ( "Home", TsDecode.succeed Home )
        , ( "End", TsDecode.succeed End )
        , ( "PageUp", TsDecode.succeed PageUp )
        , ( "PageDown", TsDecode.succeed PageDown )
        , ( "Arrow"
          , TsDecode.field "direction"
                (TsDecode.stringUnion
                    [ ( "Up", Arrow Up )
                    , ( "Down", Arrow Down )
                    , ( "Left", Arrow Left )
                    , ( "Right", Arrow Right )
                    ]
                )
          )
        , ( "FunctionKey"
          , TsDecode.field "number" TsDecode.int
                |> TsDecode.map FunctionKey
          )
        ]


charDecoder : TsDecode.Decoder Key
charDecoder =
    TsDecode.string
        |> TsDecode.andThen
            (TsDecode.andThenInit
                (\s ->
                    case String.uncons s of
                        Just ( c, _ ) ->
                            TsDecode.succeed (Character c)

                        Nothing ->
                            TsDecode.fail "Empty character"
                )
            )


decodeModifier : TsDecode.Decoder Modifier
decodeModifier =
    TsDecode.stringUnion
        [ ( "Ctrl", Ctrl )
        , ( "Alt", Alt )
        , ( "Shift", Shift )
        ]


decodeMouseEvent : TsDecode.Decoder MouseEvent
decodeMouseEvent =
    let
        coords : TsDecode.Decoder { row : Int, col : Int }
        coords =
            TsDecode.map2 (\r c -> { row = r, col = c })
                (TsDecode.field "row" TsDecode.int)
                (TsDecode.field "col" TsDecode.int)
    in
    TsDecode.discriminatedUnion "action"
        [ ( "click"
          , TsDecode.map2
                (\pos button ->
                    Click { row = pos.row, col = pos.col, button = button }
                )
                coords
                (TsDecode.field "button" decodeMouseButton)
          )
        , ( "scrollUp"
          , TsDecode.map2
                (\pos amt -> ScrollUp { row = pos.row, col = pos.col, amount = amt })
                coords
                (TsDecode.field "amount" TsDecode.int
                    |> TsDecode.maybe
                    |> TsDecode.map (Maybe.withDefault 1)
                )
          )
        , ( "scrollDown"
          , TsDecode.map2
                (\pos amt -> ScrollDown { row = pos.row, col = pos.col, amount = amt })
                coords
                (TsDecode.field "amount" TsDecode.int
                    |> TsDecode.maybe
                    |> TsDecode.map (Maybe.withDefault 1)
                )
          )
        ]


decodeMouseButton : TsDecode.Decoder MouseButton
decodeMouseButton =
    TsDecode.stringUnion
        [ ( "left", LeftButton )
        , ( "middle", MiddleButton )
        , ( "right", RightButton )
        ]
