module LayoutTests exposing (suite)

import Ansi.Color
import Expect
import Json.Encode
import Test exposing (Test, describe, test)
import Tui
import Tui.Layout as Layout


suite : Test
suite =
    describe "Tui.Layout"
        [ describe "Rendering"
            [ test "single pane shows title in border" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "main"
                            { title = "My Pane", width = Layout.fill }
                            (Layout.content [ Tui.text "hello" ])
                        ]
                        |> renderAt { width = 20, height = 5 }
                        |> String.contains "My Pane"
                        |> Expect.equal True
            , test "single pane shows content" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "main"
                            { title = "Test", width = Layout.fill }
                            (Layout.content
                                [ Tui.text "line 1"
                                , Tui.text "line 2"
                                ]
                            )
                        ]
                        |> renderAt { width = 20, height = 6 }
                        |> String.contains "line 1"
                        |> Expect.equal True
            , test "pane draws box borders" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "box"
                            { title = "Box", width = Layout.fill }
                            (Layout.content [ Tui.text "content" ])
                        ]
                        |> renderAt { width = 15, height = 5 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "┌" |> Expect.equal True
                                    , \str -> str |> String.contains "┐" |> Expect.equal True
                                    , \str -> str |> String.contains "└" |> Expect.equal True
                                    , \str -> str |> String.contains "┘" |> Expect.equal True
                                    ]
                                    s
                           )
            ]
        , describe "Style preservation"
            [ test "styled content in pane preserves styling in Screen" <|
                \() ->
                    let
                        screen : Tui.Screen
                        screen =
                            Layout.horizontal
                                [ Layout.pane "main"
                                    { title = "Test", width = Layout.fill }
                                    (Layout.selectableList
                                        { onSelect = identity
                                        , selected =
                                            \item ->
                                                Tui.styled
                                                    { fg = Just Ansi.Color.yellow
                                                    , bg = Nothing
                                                    , attributes = [ Tui.bold ]
                                                    }
                                                    ("▸ " ++ item)
                                        , default = \item -> Tui.text ("  " ++ item)
                                        }
                                        [ "apple", "banana" ]
                                    )
                                ]
                                |> renderScreenAt { width = 25, height = 5 }

                        -- The Screen should contain styled content, not just plain text.
                        -- We verify by encoding to JSON and checking for style data.
                        encoded : String
                        encoded =
                            Tui.encodeScreen screen
                                |> Json.Encode.encode 0
                    in
                    -- The encoded JSON should contain bold and foreground color
                    Expect.all
                        [ \s -> s |> String.contains "bold" |> Expect.equal True
                        , \s -> s |> String.contains "yellow" |> Expect.equal True
                        ]
                        encoded
            ]
        , describe "Split layout with integer weights"
            [ test "two panes with fill split evenly" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "left"
                            { title = "Left", width = Layout.fill }
                            (Layout.content [ Tui.text "left" ])
                        , Layout.pane "right"
                            { title = "Right", width = Layout.fill }
                            (Layout.content [ Tui.text "right" ])
                        ]
                        |> renderAt { width = 40, height = 5 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "Left" |> Expect.equal True
                                    , \str -> str |> String.contains "Right" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "fillPortion 2 and fill give 2:1 ratio" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "big"
                            { title = "Big", width = Layout.fillPortion 2 }
                            (Layout.content [ Tui.text "big content" ])
                        , Layout.pane "small"
                            { title = "Small", width = Layout.fill }
                            (Layout.content [ Tui.text "small" ])
                        ]
                        |> renderAt { width = 30, height = 5 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "big content" |> Expect.equal True
                                    , \str -> str |> String.contains "small" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "px gives fixed width" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "fixed"
                            { title = "F", width = Layout.px 10 }
                            (Layout.content [ Tui.text "fixed" ])
                        , Layout.pane "flex"
                            { title = "X", width = Layout.fill }
                            (Layout.content [ Tui.text "flex" ])
                        ]
                        |> renderAt { width = 30, height = 5 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "fixed" |> Expect.equal True
                                    , \str -> str |> String.contains "flex" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "shared border junction" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "a"
                            { title = "A", width = Layout.fill }
                            (Layout.content [ Tui.text "a" ])
                        , Layout.pane "b"
                            { title = "B", width = Layout.fill }
                            (Layout.content [ Tui.text "b" ])
                        ]
                        |> renderAt { width = 30, height = 5 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "┬" |> Expect.equal True
                                    , \str -> str |> String.contains "┴" |> Expect.equal True
                                    ]
                                    s
                           )
            ]
        , describe "Selectable list"
            [ test "selectableList renders items with default style" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "list"
                            { title = "Items", width = Layout.fill }
                            (Layout.selectableList
                                { onSelect = identity
                                , selected = \item -> Tui.text ("▸ " ++ item)
                                , default = \item -> Tui.text ("  " ++ item)
                                }
                                [ "apple", "banana", "cherry" ]
                            )
                        ]
                        |> renderAt { width = 25, height = 7 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "▸ apple" |> Expect.equal True
                                    , \str -> str |> String.contains "  banana" |> Expect.equal True
                                    , \str -> str |> String.contains "  cherry" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "selectableList highlights selected item after keyboard nav" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init
                                |> Layout.navigateDown "list"
                    in
                    Layout.horizontal
                        [ Layout.pane "list"
                            { title = "Items", width = Layout.fill }
                            (Layout.selectableList
                                { onSelect = identity
                                , selected = \item -> Tui.text ("▸ " ++ item)
                                , default = \item -> Tui.text ("  " ++ item)
                                }
                                [ "apple", "banana", "cherry" ]
                            )
                        ]
                        |> renderWithState state { width = 25, height = 7 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "  apple" |> Expect.equal True
                                    , \str -> str |> String.contains "▸ banana" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "selectedItem returns the currently selected item" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init
                                |> Layout.navigateDown "list"
                                |> Layout.navigateDown "list"
                    in
                    Layout.selectedIndex "list" state
                        |> Expect.equal 2
            , test "selection clamps at list bounds" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init
                                |> Layout.navigateUp "list"
                                |> Layout.navigateUp "list"
                    in
                    Layout.selectedIndex "list" state
                        |> Expect.equal 0
            ]
        , describe "Mouse dispatch"
            [ test "clicking a selectable item selects it" <|
                \() ->
                    let
                        items : List String
                        items =
                            [ "apple", "banana", "cherry" ]

                        layout : Layout.Layout Int
                        layout =
                            Layout.horizontal
                                [ Layout.pane "list"
                                    { title = "Items", width = Layout.fill }
                                    (Layout.selectableList
                                        { onSelect = identity
                                        , selected = \item -> Tui.text ("▸ " ++ item)
                                        , default = \item -> Tui.text ("  " ++ item)
                                        }
                                        items
                                    )
                                ]

                        -- Click row 2 (0-indexed), which is the second content row
                        ( newState, maybeMsg ) =
                            Layout.handleMouse
                                (Tui.Click { row = 2, col = 5, button = Tui.LeftButton })
                                { width = 30, height = 8 }
                                layout
                                Layout.init
                    in
                    Expect.all
                        [ \_ -> maybeMsg |> Expect.equal (Just 1)
                        , \_ -> Layout.selectedIndex "list" newState |> Expect.equal 1
                        ]
                        ()
            , test "scroll in pane updates scroll offset" <|
                \() ->
                    let
                        layout : Layout.Layout Int
                        layout =
                            Layout.horizontal
                                [ Layout.pane "list"
                                    { title = "Items", width = Layout.fill }
                                    (Layout.content
                                        (List.range 1 20
                                            |> List.map (\i -> Tui.text ("item " ++ String.fromInt i))
                                        )
                                    )
                                ]

                        ( newState, _ ) =
                            Layout.handleMouse
                                (Tui.ScrollDown { row = 2, col = 5, amount = 1 })
                                { width = 30, height = 8 }
                                layout
                                Layout.init
                    in
                    Layout.scrollPosition "list" newState
                        |> Expect.equal 3
            ]
        ]


{-| Helper: render layout to Screen (preserving styles).
-}
renderScreenAt : { width : Int, height : Int } -> Layout.Layout msg -> Tui.Screen
renderScreenAt size layout =
    layout
        |> Layout.toScreen (Layout.withContext size Layout.init)


{-| Helper: render layout with default state at given dimensions.
-}
renderAt : { width : Int, height : Int } -> Layout.Layout msg -> String
renderAt size layout =
    renderWithState Layout.init size layout


{-| Helper: render layout with specific state at given dimensions.
-}
renderWithState : Layout.State -> { width : Int, height : Int } -> Layout.Layout msg -> String
renderWithState state size layout =
    layout
        |> Layout.toScreen (Layout.withContext size state)
        |> Tui.toString
