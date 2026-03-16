module LayoutTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Layout as Layout


suite : Test
suite =
    describe "Tui.Layout"
        [ describe "Pane rendering"
            [ test "single pane with title and border" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane
                            { title = "My Pane"
                            , width = Layout.fill
                            , scroll = Layout.initScroll
                            }
                            (Tui.text "hello")
                        ]
                        |> Layout.toScreen { width = 20, height = 5 }
                        |> Tui.toString
                        |> String.contains "My Pane"
                        |> Expect.equal True
            , test "single pane shows content" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane
                            { title = "Test"
                            , width = Layout.fill
                            , scroll = Layout.initScroll
                            }
                            (Tui.lines
                                [ Tui.text "line 1"
                                , Tui.text "line 2"
                                ]
                            )
                        ]
                        |> Layout.toScreen { width = 20, height = 6 }
                        |> Tui.toString
                        |> String.contains "line 1"
                        |> Expect.equal True
            , test "pane draws box borders" <|
                \() ->
                    let
                        screen : String
                        screen =
                            Layout.horizontal
                                [ Layout.pane
                                    { title = "Box"
                                    , width = Layout.fill
                                    , scroll = Layout.initScroll
                                    }
                                    (Tui.text "content")
                                ]
                                |> Layout.toScreen { width = 15, height = 5 }
                                |> Tui.toString
                    in
                    Expect.all
                        [ \s -> s |> String.contains "┌" |> Expect.equal True
                        , \s -> s |> String.contains "┐" |> Expect.equal True
                        , \s -> s |> String.contains "└" |> Expect.equal True
                        , \s -> s |> String.contains "┘" |> Expect.equal True
                        , \s -> s |> String.contains "│" |> Expect.equal True
                        ]
                        screen
            ]
        , describe "Split layout"
            [ test "two panes side by side" <|
                \() ->
                    let
                        screen : String
                        screen =
                            Layout.horizontal
                                [ Layout.pane
                                    { title = "Left"
                                    , width = Layout.fraction (1 / 2)
                                    , scroll = Layout.initScroll
                                    }
                                    (Tui.text "left content")
                                , Layout.pane
                                    { title = "Right"
                                    , width = Layout.fill
                                    , scroll = Layout.initScroll
                                    }
                                    (Tui.text "right content")
                                ]
                                |> Layout.toScreen { width = 40, height = 6 }
                                |> Tui.toString
                    in
                    Expect.all
                        [ \s -> s |> String.contains "Left" |> Expect.equal True
                        , \s -> s |> String.contains "Right" |> Expect.equal True
                        , \s -> s |> String.contains "left content" |> Expect.equal True
                        , \s -> s |> String.contains "right content" |> Expect.equal True
                        ]
                        screen
            , test "two panes share border at junction" <|
                \() ->
                    let
                        screen : String
                        screen =
                            Layout.horizontal
                                [ Layout.pane
                                    { title = "A"
                                    , width = Layout.fraction (1 / 2)
                                    , scroll = Layout.initScroll
                                    }
                                    (Tui.text "a")
                                , Layout.pane
                                    { title = "B"
                                    , width = Layout.fill
                                    , scroll = Layout.initScroll
                                    }
                                    (Tui.text "b")
                                ]
                                |> Layout.toScreen { width = 30, height = 5 }
                                |> Tui.toString
                    in
                    -- Should have ┬ at top junction and ┴ at bottom
                    Expect.all
                        [ \s -> s |> String.contains "┬" |> Expect.equal True
                        , \s -> s |> String.contains "┴" |> Expect.equal True
                        ]
                        screen
            ]
        , describe "Scrolling"
            [ test "scroll offset clips content" <|
                \() ->
                    let
                        scroll : Layout.Scroll
                        scroll =
                            Layout.initScroll |> Layout.scrollBy 2

                        screen : String
                        screen =
                            Layout.horizontal
                                [ Layout.pane
                                    { title = "List"
                                    , width = Layout.fill
                                    , scroll = scroll
                                    }
                                    (Tui.lines
                                        [ Tui.text "line 0"
                                        , Tui.text "line 1"
                                        , Tui.text "line 2"
                                        , Tui.text "line 3"
                                        , Tui.text "line 4"
                                        ]
                                    )
                                ]
                                |> Layout.toScreen { width = 20, height = 5 }
                                |> Tui.toString
                    in
                    Expect.all
                        [ \s -> s |> String.contains "line 0" |> Expect.equal False
                        , \s -> s |> String.contains "line 1" |> Expect.equal False
                        , \s -> s |> String.contains "line 2" |> Expect.equal True
                        ]
                        screen
            , test "scrollDown updates scroll state" <|
                \() ->
                    let
                        scroll : Layout.Scroll
                        scroll =
                            Layout.initScroll
                                |> Layout.scrollBy 3
                                |> Layout.scrollBy -1
                    in
                    Layout.scrollOffset scroll
                        |> Expect.equal 2
            ]
        , describe "Mouse dispatch"
            [ test "onScroll in pane dispatches to correct handler" <|
                \() ->
                    let
                        layout : Layout.Layout Msg
                        layout =
                            Layout.horizontal
                                [ Layout.pane
                                    { title = "Left"
                                    , width = Layout.fraction (1 / 2)
                                    , scroll = Layout.initScroll
                                    }
                                    (Tui.text "left")
                                    |> Layout.onScroll LeftScroll
                                , Layout.pane
                                    { title = "Right"
                                    , width = Layout.fill
                                    , scroll = Layout.initScroll
                                    }
                                    (Tui.text "right")
                                    |> Layout.onScroll RightScroll
                                ]

                        -- Scroll in left pane (col 5, within first half of 40 cols)
                        result : Maybe Msg
                        result =
                            Layout.handleMouse
                                (Tui.ScrollDown { row = 2, col = 5, amount = 1 })
                                { width = 40, height = 6 }
                                layout
                    in
                    result
                        |> Maybe.map isLeftScroll
                        |> Expect.equal (Just True)
            , test "onClick in pane dispatches with local coordinates" <|
                \() ->
                    let
                        layout : Layout.Layout Msg
                        layout =
                            Layout.horizontal
                                [ Layout.pane
                                    { title = "List"
                                    , width = Layout.fill
                                    , scroll = Layout.initScroll
                                    }
                                    (Tui.text "items")
                                    |> Layout.onClick (\pos -> Clicked pos.row)
                                ]

                        -- Click at row 3, col 5 — pane content starts at row 1
                        result : Maybe Msg
                        result =
                            Layout.handleMouse
                                (Tui.Click { row = 3, col = 5, button = Tui.LeftButton })
                                { width = 30, height = 8 }
                                layout
                    in
                    result
                        |> Expect.equal (Just (Clicked 2))
            ]
        ]


type Msg
    = LeftScroll Layout.ScrollEvent
    | RightScroll Layout.ScrollEvent
    | Clicked Int


isLeftScroll : Msg -> Bool
isLeftScroll msg =
    case msg of
        LeftScroll _ ->
            True

        _ ->
            False
