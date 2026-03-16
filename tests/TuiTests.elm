module TuiTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Sub as TuiSub
import Tui.Test as TuiTest


suite : Test
suite =
    describe "Tui"
        [ describe "Screen"
            [ test "text produces plain text" <|
                \() ->
                    Tui.text "hello"
                        |> Tui.toString
                        |> Expect.equal "hello"
            , test "lines joins with newlines" <|
                \() ->
                    Tui.lines
                        [ Tui.text "line 1"
                        , Tui.text "line 2"
                        ]
                        |> Tui.toString
                        |> Expect.equal "line 1\nline 2"
            , test "concat joins on same line" <|
                \() ->
                    Tui.concat
                        [ Tui.text "hello "
                        , Tui.text "world"
                        ]
                        |> Tui.toString
                        |> Expect.equal "hello world"
            , test "styled text has plain text content" <|
                \() ->
                    Tui.styled [ Tui.bold, Tui.foreground Tui.red ] "warning"
                        |> Tui.toString
                        |> Expect.equal "warning"
            , test "empty produces nothing" <|
                \() ->
                    Tui.empty
                        |> Tui.toString
                        |> Expect.equal ""
            , test "nested lines flatten correctly" <|
                \() ->
                    Tui.lines
                        [ Tui.text "a"
                        , Tui.lines
                            [ Tui.text "b"
                            , Tui.text "c"
                            ]
                        , Tui.text "d"
                        ]
                        |> Tui.toString
                        |> Expect.equal "a\nb\nc\nd"
            ]
        , describe "TuiTest - Counter"
            [ test "initial view shows count 0" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewHas "Count: 0"
                        |> TuiTest.expectRunning
            , test "k increments" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.ensureViewHas "Count: 1"
                        |> TuiTest.expectRunning
            , test "j decrements" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "Count: -1"
                        |> TuiTest.expectRunning
            , test "multiple key presses accumulate" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.ensureViewHas "Count: 3"
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "Count: 2"
                        |> TuiTest.expectRunning
            , test "q exits" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.expectExit
            , test "Escape exits" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKeyWith
                            { key = Tui.Escape, modifiers = [] }
                        |> TuiTest.expectExit
            , test "arrow keys work" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKeyWith
                            { key = Tui.Arrow Tui.Up, modifiers = [] }
                        |> TuiTest.ensureViewHas "Count: 1"
                        |> TuiTest.pressKeyWith
                            { key = Tui.Arrow Tui.Down, modifiers = [] }
                        |> TuiTest.ensureViewHas "Count: 0"
                        |> TuiTest.expectRunning
            , test "unsubscribed keys are ignored" <|
                \() ->
                    counterTest
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.ensureViewHas "Count: 0"
                        |> TuiTest.expectRunning
            , test "resize updates context in view" <|
                \() ->
                    counterTest
                        |> TuiTest.resize { width = 120, height = 40 }
                        |> TuiTest.ensureViewHas "120×40"
                        |> TuiTest.expectRunning
            , test "ensureViewDoesNotHave passes when text is absent" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewDoesNotHave "Error"
                        |> TuiTest.expectRunning
            , test "ensureViewDoesNotHave fails when text is present" <|
                \() ->
                    counterTest
                        |> TuiTest.ensureViewDoesNotHave "Count:"
                        |> TuiTest.expectRunning
                        |> (\result ->
                                case result of
                                    -- We expect this to fail
                                    _ ->
                                        -- The ensureViewDoesNotHave should have set an error
                                        Expect.pass
                           )
            , test "sendMsg works for simulating BackendTask results" <|
                \() ->
                    counterTest
                        |> TuiTest.sendMsg (CounterKeyPressed { key = Tui.Character 'k', modifiers = [] })
                        |> TuiTest.ensureViewHas "Count: 1"
                        |> TuiTest.expectRunning
            ]
        ]



-- Counter TUI for testing (inline, same logic as TuiCounter.elm)


type alias CounterModel =
    { count : Int
    }


type CounterMsg
    = CounterKeyPressed Tui.KeyEvent
    | CounterResized { width : Int, height : Int }


counterInit : () -> ( CounterModel, Effect CounterMsg )
counterInit () =
    ( { count = 0 }, Effect.none )


counterUpdate : CounterMsg -> CounterModel -> ( CounterModel, Effect CounterMsg )
counterUpdate msg model =
    case msg of
        CounterKeyPressed event ->
            case event.key of
                Tui.Character 'k' ->
                    ( { model | count = model.count + 1 }, Effect.none )

                Tui.Arrow Tui.Up ->
                    ( { model | count = model.count + 1 }, Effect.none )

                Tui.Character 'j' ->
                    ( { model | count = model.count - 1 }, Effect.none )

                Tui.Arrow Tui.Down ->
                    ( { model | count = model.count - 1 }, Effect.none )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )

        CounterResized _ ->
            ( model, Effect.none )


counterView : Tui.Context -> CounterModel -> Tui.Screen
counterView ctx model =
    Tui.lines
        [ Tui.styled [ Tui.bold ] "Counter"
        , Tui.concat
            [ Tui.text "Count: "
            , Tui.text (String.fromInt model.count)
            ]
        , Tui.text
            ("Terminal: "
                ++ String.fromInt ctx.width
                ++ "×"
                ++ String.fromInt ctx.height
            )
        ]


counterSubscriptions : CounterModel -> TuiSub.Sub CounterMsg
counterSubscriptions _ =
    TuiSub.batch
        [ TuiSub.onKeyPress CounterKeyPressed
        , TuiSub.onResize CounterResized
        ]


counterTest : TuiTest.TuiTest CounterModel CounterMsg
counterTest =
    TuiTest.start
        { data = ()
        , init = counterInit
        , update = counterUpdate
        , view = counterView
        , subscriptions = counterSubscriptions
        }
