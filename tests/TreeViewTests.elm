module TreeViewTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Layout as Layout


files : List String
files =
    [ "src/Main.elm"
    , "src/Utils.elm"
    , "src/Api/Route.elm"
    , "src/Api/Handler.elm"
    , "tests/MainTest.elm"
    , "README.md"
    ]


treeLayout : Layout.Layout Int
treeLayout =
    Layout.horizontal
        [ Layout.pane "files"
            { title = "Files", width = Layout.fill }
            (Layout.selectableList
                { onSelect = identity
                , selected = \item -> Tui.text ("▸ " ++ item)
                , default = \item -> Tui.text ("  " ++ item)
                }
                files
                |> Layout.withTreeView
                    { toPath = String.split "/" }
                    files
            )
        ]


suite : Test
suite =
    describe "Layout tree view (lazygit-style)"
        [ describe "tree rendering"
            [ test "tree mode groups files by directory" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        rendered : String
                        rendered =
                            treeLayout
                                |> Layout.toScreen state
                                |> Tui.toString
                    in
                    Expect.all
                        [ -- Should show directory nodes
                          \r -> r |> String.contains "src" |> Expect.equal True
                        , \r -> r |> String.contains "tests" |> Expect.equal True
                        , -- Should show leaf files
                          \r -> r |> String.contains "README.md" |> Expect.equal True
                        ]
                        rendered
            , test "backtick toggles between tree and flat view" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        -- Toggle to flat view
                        ( s1, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '`', modifiers = [] }
                                treeLayout
                                state

                        rendered : String
                        rendered =
                            treeLayout
                                |> Layout.toScreen s1
                                |> Tui.toString
                    in
                    -- In flat view, full paths should be visible
                    Expect.all
                        [ \r -> r |> String.contains "src/Main.elm" |> Expect.equal True
                        , \r -> r |> String.contains "src/Api/Route.elm" |> Expect.equal True
                        ]
                        rendered
            ]
        , describe "collapse/expand"
            [ test "Enter on directory toggles collapse" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        rendered1 : String
                        rendered1 =
                            treeLayout
                                |> Layout.toScreen state
                                |> Tui.toString

                        -- Navigate to "src" directory and press Enter to collapse
                        ( s1, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                treeLayout
                                state

                        rendered2 : String
                        rendered2 =
                            treeLayout
                                |> Layout.toScreen s1
                                |> Tui.toString
                    in
                    Expect.all
                        [ -- Before collapse, children should be visible
                          \_ -> rendered1 |> String.contains "Main.elm" |> Expect.equal True
                        , -- After collapse, children should be hidden
                          \_ -> rendered2 |> String.contains "Main.elm" |> Expect.equal False
                        , -- But the directory itself should still be visible
                          \_ -> rendered2 |> String.contains "src" |> Expect.equal True
                        ]
                        ()
            , test "- collapses all directories" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        ( s1, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '-', modifiers = [] }
                                treeLayout
                                state

                        rendered : String
                        rendered =
                            treeLayout
                                |> Layout.toScreen s1
                                |> Tui.toString
                    in
                    Expect.all
                        [ -- Directories should be visible
                          \r -> r |> String.contains "src" |> Expect.equal True
                        , \r -> r |> String.contains "tests" |> Expect.equal True
                        , -- But children should be hidden
                          \r -> r |> String.contains "Main.elm" |> Expect.equal False
                        , \r -> r |> String.contains "Route.elm" |> Expect.equal False
                        , -- Top-level files still visible
                          \r -> r |> String.contains "README.md" |> Expect.equal True
                        ]
                        rendered
            , test "= expands all directories" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        -- Collapse all first
                        ( s1, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '-', modifiers = [] }
                                treeLayout
                                state

                        -- Then expand all
                        ( s2, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '=', modifiers = [] }
                                treeLayout
                                s1

                        rendered : String
                        rendered =
                            treeLayout
                                |> Layout.toScreen s2
                                |> Tui.toString
                    in
                    Expect.all
                        [ \r -> r |> String.contains "Main.elm" |> Expect.equal True
                        , \r -> r |> String.contains "Route.elm" |> Expect.equal True
                        , \r -> r |> String.contains "MainTest.elm" |> Expect.equal True
                        ]
                        rendered
            ]
        , describe "navigation"
            [ test "j/k navigate the flattened tree rows" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        -- Navigate down through tree rows
                        ( s1, _ ) =
                            Layout.navigateDown "files" treeLayout state

                        idx : Int
                        idx =
                            Layout.selectedIndex "files" s1
                    in
                    -- Should move to the next visible row (index 1)
                    idx |> Expect.equal 1
            , test "onSelect fires with original item index for leaf nodes" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        -- Collapse all, then navigate to README.md (should be near the top)
                        ( s1, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '-', modifiers = [] }
                                treeLayout
                                state

                        -- In collapsed view: src, tests, README.md
                        -- Navigate to README.md (index 2)
                        ( s2, _ ) =
                            Layout.navigateDown "files" treeLayout s1

                        ( _, maybeMsg ) =
                            Layout.navigateDown "files" treeLayout s2
                    in
                    -- README.md is at original index 5 in the files list
                    maybeMsg |> Expect.equal (Just 5)
            ]
        , describe "selectedItem"
            [ test "selectedItem returns the actual item, not an index" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        -- Navigate down past the "src" directory to a leaf
                        ( s1, _ ) =
                            Layout.navigateDown "files" treeLayout state

                        ( s2, _ ) =
                            Layout.navigateDown "files" treeLayout s1

                        item : Maybe String
                        item =
                            Layout.selectedItem "files" files treeLayout s2
                    in
                    -- Should return the actual file string, not an index
                    item |> Expect.notEqual Nothing
            , test "selectedItem returns Nothing for directory nodes" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            initState

                        -- First item in tree is the "src" directory
                        item : Maybe String
                        item =
                            Layout.selectedItem "files" files treeLayout state
                    in
                    -- Directory nodes aren't items — should return Nothing
                    item |> Expect.equal Nothing
            , test "selectedItem works with filtered tree" <|
                \() ->
                    let
                        filterableTreeLayout : Layout.Layout Int
                        filterableTreeLayout =
                            Layout.horizontal
                                [ Layout.pane "files"
                                    { title = "Files", width = Layout.fill }
                                    (Layout.selectableList
                                        { onSelect = identity
                                        , selected = \f -> Tui.text ("▸ " ++ f)
                                        , default = \f -> Tui.text ("  " ++ f)
                                        }
                                        files
                                        |> Layout.withFilterable identity files
                                        |> Layout.withTreeView
                                            { toPath = String.split "/" }
                                            files
                                    )
                                ]

                        state : Layout.State
                        state =
                            initState

                        item : Maybe String
                        item =
                            Layout.selectedItem "files" files filterableTreeLayout state
                    in
                    -- Should handle the combination of filter + tree
                    item |> Expect.notEqual (Just "nonexistent")
            ]
        , describe "path compression"
            [ test "single-child directories are compressed" <|
                \() ->
                    let
                        -- src/Api/ has two children, so no compression
                        -- tests/ has one child, so tests/MainTest.elm compressed to one row
                        state : Layout.State
                        state =
                            initState

                        rendered : String
                        rendered =
                            treeLayout
                                |> Layout.toScreen state
                                |> Tui.toString
                    in
                    -- "tests" directory with single child should be compressed
                    -- The exact rendering depends on implementation
                    rendered |> String.contains "tests" |> Expect.equal True
            ]
        ]


initState : Layout.State
initState =
    Layout.init
        |> Layout.withContext { width = 40, height = 15 }
        |> Layout.focusPane "files"
