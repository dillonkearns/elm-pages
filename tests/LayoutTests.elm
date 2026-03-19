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
                                    [ \str -> str |> String.contains "╭" |> Expect.equal True
                                    , \str -> str |> String.contains "╮" |> Expect.equal True
                                    , \str -> str |> String.contains "╰" |> Expect.equal True
                                    , \str -> str |> String.contains "╯" |> Expect.equal True
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
                                                    , attributes = [ Tui.Bold ]
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
            , test "separate pane boxes with gap" <|
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
                                    [ \str -> str |> String.contains "╮ ╭" |> Expect.equal True
                                    , \str -> str |> String.contains "╯ ╰" |> Expect.equal True
                                    ]
                                    s
                           )
            ]
        , describe "Navigate with auto-scroll (lazygit-style)"
            [ test "navigateDown fires onSelect with new index" <|
                \() ->
                    let
                        ( _, maybeMsg ) =
                            Layout.navigateDown "list" tallList
                                (Layout.init |> Layout.withContext { width = 30, height = 12 })
                    in
                    maybeMsg |> Expect.equal (Just 1)
            , test "navigateDown fires onSelect at boundary (Nothing when clamped)" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init |> Layout.withContext { width = 30, height = 12 }

                        -- Navigate 20 times on a 10-item list
                        ( _, lastMsg ) =
                            List.range 1 20
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateDown "list" tallList s)
                                    ( state, Nothing )
                    in
                    -- Last navigate was at boundary, should be Nothing
                    lastMsg |> Expect.equal Nothing
            , test "navigateDown clamps selectedIndex at item count" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init |> Layout.withContext { width = 30, height = 12 }

                        ( finalState, _ ) =
                            List.range 1 20
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateDown "list" tallList s)
                                    ( state, Nothing )
                    in
                    Layout.selectedIndex "list" finalState |> Expect.equal 9
            , test "navigateUp fires Nothing when already at 0" <|
                \() ->
                    let
                        ( _, maybeMsg ) =
                            Layout.navigateUp "list" tallList
                                (Layout.init |> Layout.withContext { width = 30, height = 12 })
                    in
                    maybeMsg |> Expect.equal Nothing
            , test "scrolling down keeps items visible below selection" <|
                \() ->
                    -- Navigate down repeatedly. The selection should stay in view
                    -- with scroll padding (items visible below it)
                    let
                        state : Layout.State
                        state =
                            Layout.init |> Layout.withContext { width = 30, height = 7 }

                        -- Height 7 = 5 visible content rows (minus 2 for borders)
                        -- Navigate down 6 times (to index 6, past the viewport)
                        ( finalState, _ ) =
                            List.range 1 6
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateDown "list" tallList s)
                                    ( state, Nothing )
                    in
                    -- The selected item (index 6) should be visible in the rendered output
                    tallList
                        |> renderWithState finalState { width = 30, height = 7 }
                        |> String.contains "▸ item 6"
                        |> Expect.equal True
            , test "scrolling down keeps 2 items below selection" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init |> Layout.withContext { width = 30, height = 7 }

                        -- Navigate to index 6
                        ( finalState, _ ) =
                            List.range 1 6
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateDown "list" tallList s)
                                    ( state, Nothing )
                    in
                    -- Items 7 and 8 (indices after selection) should still be visible
                    tallList
                        |> renderWithState finalState { width = 30, height = 7 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "item 7" |> Expect.equal True
                                    , \str -> str |> String.contains "item 8" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "scrolling up keeps selection visible" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init |> Layout.withContext { width = 30, height = 7 }

                        -- Navigate down to index 8, then back up to 2
                        ( downState, _ ) =
                            List.range 1 8
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateDown "list" tallList s)
                                    ( state, Nothing )

                        ( upState, _ ) =
                            List.range 1 6
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateUp "list" tallList s)
                                    ( downState, Nothing )
                    in
                    -- Selected item (index 2) should be visible
                    tallList
                        |> renderWithState upState { width = 30, height = 7 }
                        |> String.contains "▸ item 2"
                        |> Expect.equal True
            , test "mouse scroll takes selection out of view, j snaps back" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init |> Layout.withContext { width = 30, height = 7 }

                        -- Selection is at index 0, mouse scroll down moves viewport
                        scrolledState : Layout.State
                        scrolledState =
                            Layout.scrollDown "list" 6 state

                        -- Now press j (navigateDown) — should snap selection into view
                        ( snappedState, _ ) =
                            Layout.navigateDown "list" tallList scrolledState

                        snappedIndex : Int
                        snappedIndex =
                            Layout.selectedIndex "list" snappedState
                    in
                    -- Selection should be visible after snapping
                    tallList
                        |> renderWithState snappedState { width = 30, height = 7 }
                        |> String.contains ("▸ item " ++ String.fromInt snappedIndex)
                        |> Expect.equal True
            , test "mouse scroll takes selection out of view, k snaps back" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init |> Layout.withContext { width = 30, height = 7 }

                        -- Navigate to index 9 first
                        ( downState, _ ) =
                            List.range 1 9
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateDown "list" tallList s)
                                    ( state, Nothing )

                        -- Mouse scroll up moves viewport to top
                        scrolledState : Layout.State
                        scrolledState =
                            Layout.scrollUp "list" 20 downState

                        -- Press k — should snap selection into view
                        ( snappedState, _ ) =
                            Layout.navigateUp "list" tallList scrolledState

                        snappedIndex : Int
                        snappedIndex =
                            Layout.selectedIndex "list" snappedState
                    in
                    tallList
                        |> renderWithState snappedState { width = 30, height = 7 }
                        |> String.contains ("▸ item " ++ String.fromInt snappedIndex)
                        |> Expect.equal True
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
                        list : Layout.Layout Int
                        list =
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

                        ( state, _ ) =
                            Layout.navigateDown "list" list
                                (Layout.init |> Layout.withContext { width = 25, height = 7 })
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
                        ( state, _ ) =
                            Layout.navigateDown "list" tallList
                                (Layout.init |> Layout.withContext { width = 25, height = 7 })
                                |> (\( s, _ ) -> Layout.navigateDown "list" tallList s)
                    in
                    Layout.selectedIndex "list" state
                        |> Expect.equal 2
            , test "selection clamps at lower bound" <|
                \() ->
                    let
                        ( state, _ ) =
                            Layout.navigateUp "list" tallList
                                (Layout.init |> Layout.withContext { width = 25, height = 7 })
                                |> (\( s, _ ) -> Layout.navigateUp "list" tallList s)
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
        , describe "Scrollbar"
            [ test "scrollbar shows on right border when content overflows" <|
                \() ->
                    tallList
                        |> renderAt { width = 30, height = 7 }
                        |> String.contains "█"
                        |> Expect.equal True
            , test "two-pane layout has scrollbar as shared border" <|
                \() ->
                    let
                        twoPane : Layout.Layout Int
                        twoPane =
                            Layout.horizontal
                                [ Layout.pane "left"
                                    { title = "L", width = Layout.fill }
                                    (Layout.selectableList
                                        { onSelect = identity
                                        , selected = \item -> Tui.text ("▸ " ++ item)
                                        , default = \item -> Tui.text ("  " ++ item)
                                        }
                                        (List.range 0 20 |> List.map (\i -> "item " ++ String.fromInt i))
                                    )
                                , Layout.pane "right"
                                    { title = "R", width = Layout.fill }
                                    (Layout.content [ Tui.text "detail" ])
                                ]

                        rendered : String
                        rendered =
                            renderAt { width = 40, height = 10 } twoPane

                        contentLines : List String
                        contentLines =
                            rendered
                                |> String.lines
                                |> List.filter (String.contains "item")
                    in
                    -- Scrollbar █ should appear (left pane has 20+ items in 8 visible rows)
                    -- It should NOT have █│ (double border) — █ IS the shared border
                    Expect.all
                        [ \lines -> lines |> List.any (String.contains "█") |> Expect.equal True
                        , \lines -> lines |> List.any (String.contains "█│") |> Expect.equal False
                        ]
                        contentLines
            ]
        , describe "Focus"
            [ test "focused pane border contains green styling" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init |> Layout.focusPane "left"

                        screen : Tui.Screen
                        screen =
                            Layout.horizontal
                                [ Layout.pane "left"
                                    { title = "Left", width = Layout.fill }
                                    (Layout.content [ Tui.text "a" ])
                                , Layout.pane "right"
                                    { title = "Right", width = Layout.fill }
                                    (Layout.content [ Tui.text "b" ])
                                ]
                                |> Layout.toScreen (Layout.withContext { width = 40, height = 5 } state)

                        encoded : String
                        encoded =
                            Tui.encodeScreen screen |> Json.Encode.encode 0
                    in
                    -- Focused pane border should have green color
                    encoded
                        |> String.contains "green"
                        |> Expect.equal True
            , test "focusedPane returns the focused pane id" <|
                \() ->
                    Layout.init
                        |> Layout.focusPane "commits"
                        |> Layout.focusedPane
                        |> Expect.equal (Just "commits")
            , test "no focus by default" <|
                \() ->
                    Layout.init
                        |> Layout.focusedPane
                        |> Expect.equal Nothing
            ]
        , describe "Pane groups (tabs)"
            [ test "paneGroup shows active tab content" <|
                \() ->
                    Layout.horizontal
                        [ Layout.paneGroup "left"
                            { tabs =
                                [ { id = "files", label = "Files", content = Layout.content [ Tui.text "file-content" ] }
                                , { id = "worktrees", label = "Worktrees", content = Layout.content [ Tui.text "worktree-content" ] }
                                ]
                            , activeTab = "files"
                            , width = Layout.fill
                            }
                        ]
                        |> renderAt { width = 30, height = 5 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "file-content" |> Expect.equal True
                                    , \str -> str |> String.contains "worktree-content" |> Expect.equal False
                                    ]
                                    s
                           )
            , test "paneGroup shows other tab content when switched" <|
                \() ->
                    Layout.horizontal
                        [ Layout.paneGroup "left"
                            { tabs =
                                [ { id = "files", label = "Files", content = Layout.content [ Tui.text "file-content" ] }
                                , { id = "worktrees", label = "Worktrees", content = Layout.content [ Tui.text "worktree-content" ] }
                                ]
                            , activeTab = "worktrees"
                            , width = Layout.fill
                            }
                        ]
                        |> renderAt { width = 40, height = 5 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "worktree-content" |> Expect.equal True
                                    , \str -> str |> String.contains "file-content" |> Expect.equal False
                                    ]
                                    s
                           )
            , test "paneGroup shows tab labels in title" <|
                \() ->
                    Layout.horizontal
                        [ Layout.paneGroup "left"
                            { tabs =
                                [ { id = "files", label = "Files", content = Layout.content [] }
                                , { id = "worktrees", label = "Worktrees", content = Layout.content [] }
                                ]
                            , activeTab = "files"
                            , width = Layout.fill
                            }
                        ]
                        |> renderAt { width = 40, height = 5 }
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "Files" |> Expect.equal True
                                    , \str -> str |> String.contains "Worktrees" |> Expect.equal True
                                    ]
                                    s
                           )
            , test "paneGroup preserves selection state per tab" <|
                \() ->
                    let
                        filesTabLayout : Layout.Layout Int
                        filesTabLayout =
                            Layout.horizontal
                                [ Layout.paneGroup "left"
                                    { tabs =
                                        [ { id = "files"
                                          , label = "Files"
                                          , content =
                                                Layout.selectableList
                                                    { onSelect = identity
                                                    , selected = \item -> Tui.text ("▸ " ++ item)
                                                    , default = \item -> Tui.text ("  " ++ item)
                                                    }
                                                    [ "a.elm", "b.elm", "c.elm" ]
                                          }
                                        , { id = "worktrees"
                                          , label = "Worktrees"
                                          , content = Layout.content [ Tui.text "wt" ]
                                          }
                                        ]
                                    , activeTab = "files"
                                    , width = Layout.fill
                                    }
                                ]

                        state : Layout.State
                        state =
                            Layout.init |> Layout.withContext { width = 30, height = 8 }

                        -- Navigate down in files tab using the GROUP id
                        ( stateAfterNav, _ ) =
                            Layout.navigateDown "left" filesTabLayout state
                    in
                    -- The files tab should still have index 1 selected via group ID
                    Layout.selectedIndex "left" stateAfterNav
                        |> Expect.equal 1
            ]
        , describe "Title badges and footer"
            [ test "pane with prefix shows it in border" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "commits"
                            { title = "Commits", width = Layout.fill }
                            (Layout.content [ Tui.text "a" ])
                            |> Layout.withPrefix "[4]"
                        ]
                        |> renderAt { width = 30, height = 5 }
                        |> String.contains "[4]"
                        |> Expect.equal True
            , test "pane with footer shows count on bottom border" <|
                \() ->
                    Layout.horizontal
                        [ Layout.pane "commits"
                            { title = "Commits", width = Layout.fill }
                            (Layout.content [ Tui.text "a" ])
                            |> Layout.withFooter "3 of 300"
                        ]
                        |> renderAt { width = 30, height = 5 }
                        |> String.contains "3 of 300"
                        |> Expect.equal True
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


{-| A 10-item selectable list for testing scroll behavior.
-}
tallList : Layout.Layout Int
tallList =
    Layout.horizontal
        [ Layout.pane "list"
            { title = "Items", width = Layout.fill }
            (Layout.selectableList
                { onSelect = identity
                , selected = \item -> Tui.text ("▸ " ++ item)
                , default = \item -> Tui.text ("  " ++ item)
                }
                (List.range 0 9 |> List.map (\i -> "item " ++ String.fromInt i))
            )
        ]
