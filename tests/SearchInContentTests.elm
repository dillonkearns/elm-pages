module SearchInContentTests exposing (suite)

import Ansi.Color
import Expect
import Json.Encode
import Test exposing (Test, describe, test)
import Tui
import Tui.Layout as Layout


diffLines : List Tui.Screen
diffLines =
    [ Tui.text "commit abc1234"
    , Tui.text "Author: Test User"
    , Tui.text "Date: 2026-03-21"
    , Tui.text ""
    , Tui.text "    Fix parser bug"
    , Tui.text "---"
    , Tui.text "+ added new function"
    , Tui.text "- removed old function"
    , Tui.text "+ added another function"
    , Tui.text "  unchanged line"
    , Tui.text "+ added final function"
    ]


searchableLayout : Layout.Layout Int
searchableLayout =
    Layout.horizontal
        [ Layout.pane "list"
            { title = "Items", width = Layout.fill }
            (Layout.selectableList
                { onSelect = identity
                , selected = \item -> Tui.text ("▸ " ++ item)
                , default = \item -> Tui.text ("  " ++ item)
                }
                [ "one", "two", "three" ]
            )
        , Layout.pane "diff"
            { title = "Diff", width = Layout.fill }
            (Layout.content diffLines
                |> Layout.withSearchable
            )
        ]


suite : Test
suite =
    describe "Layout content search (lazygit-style)"
        [ describe "starting a search"
            [ test "/ on searchable pane activates search mode" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        ( newState, _, handled ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                searchableLayout
                                state
                    in
                    Expect.all
                        [ \_ -> handled |> Expect.equal True
                        , \_ -> Layout.isSearchActive "diff" newState |> Expect.equal True
                        ]
                        ()
            , test "/ on non-searchable static pane does nothing" <|
                \() ->
                    let
                        nonSearchable =
                            Layout.horizontal
                                [ Layout.pane "plain"
                                    { title = "Plain", width = Layout.fill }
                                    (Layout.content [ Tui.text "hello" ])
                                ]

                        state =
                            initState |> Layout.focusPane "plain"

                        ( _, _, handled ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                nonSearchable
                                state
                    in
                    handled |> Expect.equal False
            ]
        , describe "typing does not search live (lazygit behavior)"
            [ test "typing in search prompt does not highlight yet" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            startSearchWith "added" state

                        -- Before Enter, no search results computed
                        status =
                            Layout.searchStatusBar "diff" s
                                |> Maybe.map Tui.toString
                    in
                    -- Should show "Search: added" (prompt still active)
                    status |> Expect.equal (Just "Search: added")
            ]
        , describe "Enter commits search"
            [ test "Enter computes matches and shows count" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s1 =
                            startSearchWith "added" state

                        ( s2, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                searchableLayout
                                s1

                        status =
                            Layout.searchStatusBar "diff" s2
                                |> Maybe.map Tui.toString
                    in
                    -- "added" appears on lines 6, 8, 10 (3 matches)
                    Expect.all
                        [ \s -> s |> Maybe.withDefault "" |> String.contains "1 of 3" |> Expect.equal True
                        , \s -> s |> Maybe.withDefault "" |> String.contains "added" |> Expect.equal True
                        ]
                        status
            , test "Enter with empty query cancels search" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        ( s1, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                searchableLayout
                                state

                        ( s2, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                searchableLayout
                                s1
                    in
                    Layout.isSearchActive "diff" s2 |> Expect.equal False
            ]
        , describe "n/N navigate between matches"
            [ test "n moves to next match" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            commitSearch "added" state

                        ( s2, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character 'n', modifiers = [] }
                                searchableLayout
                                s

                        status =
                            Layout.searchStatusBar "diff" s2
                                |> Maybe.map Tui.toString
                    in
                    status |> Maybe.withDefault "" |> String.contains "2 of 3" |> Expect.equal True
            , test "N moves to previous match" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            commitSearch "added" state

                        -- N from first match wraps to last
                        ( s2, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character 'N', modifiers = [] }
                                searchableLayout
                                s

                        status =
                            Layout.searchStatusBar "diff" s2
                                |> Maybe.map Tui.toString
                    in
                    status |> Maybe.withDefault "" |> String.contains "3 of 3" |> Expect.equal True
            , test "n wraps around from last to first" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            commitSearch "added" state

                        -- n three times: 1→2→3→1 (wraps)
                        s2 =
                            pressN 3 s

                        status =
                            Layout.searchStatusBar "diff" s2
                                |> Maybe.map Tui.toString
                    in
                    status |> Maybe.withDefault "" |> String.contains "1 of 3" |> Expect.equal True
            , test "n is intercepted (returns True) during active search" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            commitSearch "added" state

                        ( _, _, handled ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character 'n', modifiers = [] }
                                searchableLayout
                                s
                    in
                    handled |> Expect.equal True
            ]
        , describe "Escape clears search"
            [ test "Escape while typing clears search" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            startSearchWith "added" state

                        ( s2, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Escape, modifiers = [] }
                                searchableLayout
                                s
                    in
                    Layout.isSearchActive "diff" s2 |> Expect.equal False
            , test "Escape after Enter clears search" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            commitSearch "added" state

                        ( s2, _, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Escape, modifiers = [] }
                                searchableLayout
                                s
                    in
                    Layout.isSearchActive "diff" s2 |> Expect.equal False
            ]
        , describe "match highlighting"
            [ test "current match has cyan background in encoded output" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            commitSearch "added" state

                        encoded =
                            searchableLayout
                                |> Layout.toScreen s
                                |> Tui.encodeScreen
                                |> Json.Encode.encode 0
                    in
                    -- Current match should have cyan background
                    encoded |> String.contains "cyan" |> Expect.equal True
            , test "other matches have yellow background" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            commitSearch "added" state

                        encoded =
                            searchableLayout
                                |> Layout.toScreen s
                                |> Tui.encodeScreen
                                |> Json.Encode.encode 0
                    in
                    encoded |> String.contains "yellow" |> Expect.equal True
            ]
        , describe "search status bar"
            [ test "no search returns Nothing" <|
                \() ->
                    Layout.searchStatusBar "diff" initState |> Expect.equal Nothing
            , test "activeFilterStatusBar also returns search status" <|
                \() ->
                    let
                        state =
                            initState |> Layout.focusPane "diff"

                        s =
                            commitSearch "added" state

                        status =
                            Layout.activeFilterStatusBar s
                                |> Maybe.map Tui.toString
                    in
                    status |> Maybe.withDefault "" |> String.contains "added" |> Expect.equal True
            ]
        ]


initState : Layout.State
initState =
    Layout.init |> Layout.withContext { width = 60, height = 15 }


startSearchWith : String -> Layout.State -> Layout.State
startSearchWith query state =
    let
        ( s1, _, _ ) =
            Layout.handleKeyEvent
                { key = Tui.Character '/', modifiers = [] }
                searchableLayout
                state
    in
    query
        |> String.toList
        |> List.foldl
            (\c ( s, _, _ ) ->
                Layout.handleKeyEvent
                    { key = Tui.Character c, modifiers = [] }
                    searchableLayout
                    s
            )
            ( s1, Nothing, False )
        |> (\( s, _, _ ) -> s)


commitSearch : String -> Layout.State -> Layout.State
commitSearch query state =
    let
        s1 =
            startSearchWith query state

        ( s2, _, _ ) =
            Layout.handleKeyEvent
                { key = Tui.Enter, modifiers = [] }
                searchableLayout
                s1
    in
    s2


pressN : Int -> Layout.State -> Layout.State
pressN count state =
    List.range 1 count
        |> List.foldl
            (\_ s ->
                Layout.handleKeyEvent
                    { key = Tui.Character 'n', modifiers = [] }
                    searchableLayout
                    s
                    |> (\( st, _, _ ) -> st)
            )
            state
