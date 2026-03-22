module FilterTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Layout as Layout


items : List String
items =
    [ "apple", "apricot", "banana", "blueberry", "cherry", "date", "elderberry", "fig", "grape" ]


filterableList : Layout.Layout Int
filterableList =
    Layout.horizontal
        [ Layout.pane "fruits"
            { title = "Fruits", width = Layout.fill }
            (Layout.selectableList
                { onSelect = identity
                , selected = \item -> Tui.text ("▸ " ++ item)
                , default = \item -> Tui.text ("  " ++ item)
                }
                items
                |> Layout.withFilterable identity items
            )
        ]


suite : Test
suite =
    describe "Layout filter (lazygit-style)"
        [ describe "starting a filter"
            [ test "pressing / activates filter mode" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        ( newState, handled ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                filterableList
                                state
                    in
                    Expect.all
                        [ \_ -> handled |> Expect.equal True
                        , \_ -> Layout.isFilterActive "fruits" newState |> Expect.equal True
                        ]
                        ()
            , test "/ only works on panes with filterable content" <|
                \() ->
                    let
                        nonFilterableLayout =
                            Layout.horizontal
                                [ Layout.pane "plain"
                                    { title = "Plain", width = Layout.fill }
                                    (Layout.selectableList
                                        { onSelect = identity
                                        , selected = \item -> Tui.text ("▸ " ++ item)
                                        , default = \item -> Tui.text ("  " ++ item)
                                        }
                                        items
                                    )
                                ]

                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "plain"

                        ( _, handled ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                nonFilterableLayout
                                state
                    in
                    handled |> Expect.equal False
            ]
        , describe "typing filters in real-time"
            [ test "typing a character filters the list" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Start filter
                        ( s1, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                filterableList
                                s1Init

                        s1Init =
                            state

                        -- Type 'b' — should match "banana", "blueberry"
                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character 'b', modifiers = [] }
                                filterableList
                                s1

                        rendered =
                            filterableList
                                |> Layout.toScreen s2
                                |> Tui.toString
                    in
                    Expect.all
                        [ -- "banana" and "blueberry" should be visible
                          \s -> s |> String.contains "banana" |> Expect.equal True
                        , \s -> s |> String.contains "blueberry" |> Expect.equal True
                        , -- "apple" should be filtered out
                          \s -> s |> String.contains "apple" |> Expect.equal False
                        , -- "cherry" should be filtered out
                          \s -> s |> String.contains "cherry" |> Expect.equal False
                        ]
                        rendered
            , test "typing resets selection to 0" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Navigate to index 5 first
                        ( navState, _ ) =
                            List.range 1 5
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateDown "fruits" filterableList s)
                                    ( state, Nothing )

                        -- Start filter and type
                        ( s1, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                filterableList
                                navState

                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character 'a', modifiers = [] }
                                filterableList
                                s1
                    in
                    Layout.selectedIndex "fruits" s2 |> Expect.equal 0
            ]
        , describe "Enter applies filter"
            [ test "Enter dismisses input but keeps filter" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Start filter, type "berry"
                        ( s1, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                filterableList
                                state

                        ( s2, _ ) =
                            "berry"
                                |> String.toList
                                |> List.foldl
                                    (\c ( s, _ ) ->
                                        Layout.handleKeyEvent
                                            { key = Tui.Character c, modifiers = [] }
                                            filterableList
                                            s
                                    )
                                    ( s1, False )

                        -- Press Enter
                        ( s3, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                filterableList
                                s2

                        rendered =
                            filterableList
                                |> Layout.toScreen s3
                                |> Tui.toString
                    in
                    Expect.all
                        [ -- Filter should still be active
                          \_ -> Layout.isFilterActive "fruits" s3 |> Expect.equal True
                        , -- "blueberry" and "elderberry" should be visible
                          \s -> s |> String.contains "blueberry" |> Expect.equal True
                        , \s -> s |> String.contains "elderberry" |> Expect.equal True
                        , -- "apple" should be filtered out
                          \s -> s |> String.contains "apple" |> Expect.equal False
                        ]
                        rendered
            , test "Enter with empty query cancels filter" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Start filter then immediately Enter (empty query)
                        ( s1, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                filterableList
                                state

                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                filterableList
                                s1
                    in
                    Layout.isFilterActive "fruits" s2 |> Expect.equal False
            ]
        , describe "Escape clears filter"
            [ test "Escape while typing clears filter" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Start filter, type something
                        ( s1, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                filterableList
                                state

                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character 'b', modifiers = [] }
                                filterableList
                                s1

                        -- Press Escape
                        ( s3, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Escape, modifiers = [] }
                                filterableList
                                s2

                        rendered =
                            filterableList
                                |> Layout.toScreen s3
                                |> Tui.toString
                    in
                    Expect.all
                        [ -- Filter should be cleared
                          \_ -> Layout.isFilterActive "fruits" s3 |> Expect.equal False
                        , -- All items should be visible again
                          \s -> s |> String.contains "apple" |> Expect.equal True
                        , \s -> s |> String.contains "cherry" |> Expect.equal True
                        ]
                        rendered
            , test "Escape after Enter clears filter" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Start, type, Enter, then Escape
                        ( s1, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                filterableList
                                state

                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character 'b', modifiers = [] }
                                filterableList
                                s1

                        ( s3, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                filterableList
                                s2

                        ( s4, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Escape, modifiers = [] }
                                filterableList
                                s3
                    in
                    Layout.isFilterActive "fruits" s4 |> Expect.equal False
            ]
        , describe "Escape clears filter even after switching panes"
            [ test "Escape clears filter on original pane after switching away" <|
                \() ->
                    let
                        twoPanes =
                            Layout.horizontal
                                [ Layout.pane "left"
                                    { title = "Left", width = Layout.fill }
                                    (Layout.selectableList
                                        { onSelect = identity
                                        , selected = \item -> Tui.text ("▸ " ++ item)
                                        , default = \item -> Tui.text ("  " ++ item)
                                        }
                                        [ "apple", "banana", "cherry" ]
                                        |> Layout.withFilterable identity [ "apple", "banana", "cherry" ]
                                    )
                                , Layout.pane "right"
                                    { title = "Right", width = Layout.fill }
                                    (Layout.content [ Tui.text "details" ])
                                ]

                        state =
                            Layout.init
                                |> Layout.withContext { width = 50, height = 10 }
                                |> Layout.focusPane "left"

                        -- Filter on left pane, apply with Enter
                        s1 =
                            startFilterWithLayout "an" twoPanes state

                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                twoPanes
                                s1

                        -- Switch focus to right pane
                        s3 =
                            Layout.focusPane "right" s2

                        -- Escape should clear the filter on left pane, NOT fall through
                        ( s4, handled ) =
                            Layout.handleKeyEvent
                                { key = Tui.Escape, modifiers = [] }
                                twoPanes
                                s3
                    in
                    Expect.all
                        [ \_ -> handled |> Expect.equal True
                        , \_ -> Layout.isFilterActive "left" s4 |> Expect.equal False
                        ]
                        ()
            ]
        , describe "onSelect fires with original index"
            [ test "clicking filtered item fires original index" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Start filter, type "b", Enter
                        ( s1, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                filterableList
                                state

                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character 'b', modifiers = [] }
                                filterableList
                                s1

                        ( s3, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                filterableList
                                s2

                        -- Navigate down once (from "banana" to "blueberry")
                        ( s4, maybeMsg ) =
                            Layout.navigateDown "fruits" filterableList s3
                    in
                    -- "blueberry" is at original index 3
                    maybeMsg |> Expect.equal (Just 3)
            ]
        , describe "selection preserved on filter clear (lazygit behavior)"
            [ test "Escape preserves selected item from filtered list" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Filter to "berry" → blueberry(3), elderberry(6)
                        s1 =
                            startFilterWith "berry" state

                        -- Enter to apply filter
                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                filterableList
                                s1

                        -- Navigate down to elderberry (filtered index 1)
                        ( s3, _ ) =
                            Layout.navigateDown "fruits" filterableList s2

                        -- Escape clears filter
                        ( s4, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Escape, modifiers = [] }
                                filterableList
                                s3

                        -- elderberry is at original index 6
                        rendered =
                            filterableList
                                |> Layout.toScreen s4
                                |> Tui.toString
                    in
                    Expect.all
                        [ -- Filter should be cleared
                          \_ -> Layout.isFilterActive "fruits" s4 |> Expect.equal False
                        , -- elderberry should be selected (▸ prefix)
                          \r -> r |> String.contains "▸ elderberry" |> Expect.equal True
                        , -- All items should be visible
                          \r -> r |> String.contains "apple" |> Expect.equal True
                        , \r -> r |> String.contains "cherry" |> Expect.equal True
                        , -- Original index should be 6
                          \_ -> Layout.selectedIndex "fruits" s4 |> Expect.equal 6
                        ]
                        rendered
            , test "Escape while typing preserves current selection" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Navigate to cherry (index 4) first
                        ( navState, _ ) =
                            List.range 1 4
                                |> List.foldl
                                    (\_ ( s, _ ) -> Layout.navigateDown "fruits" filterableList s)
                                    ( state, Nothing )

                        -- Start filter (resets to 0), type "a" → apple(0), apricot(1), banana(2), date(5), grape(8)
                        s1 =
                            startFilterWith "a" navState

                        -- Navigate to banana (filtered index 2 → original index 2)
                        ( s2, _ ) =
                            Layout.navigateDown "fruits" filterableList s1

                        ( s3, _ ) =
                            Layout.navigateDown "fruits" filterableList s2

                        -- Escape
                        ( s4, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Escape, modifiers = [] }
                                filterableList
                                s3
                    in
                    Expect.all
                        [ \_ -> Layout.isFilterActive "fruits" s4 |> Expect.equal False
                        , -- banana is at original index 2
                          \_ -> Layout.selectedIndex "fruits" s4 |> Expect.equal 2
                        ]
                        ()
            ]
        , describe "multi-pane filter isolation"
            [ test "filter only affects the focused pane, not others" <|
                \() ->
                    let
                        twoFilterablePanes =
                            Layout.horizontal
                                [ Layout.pane "modules"
                                    { title = "Modules", width = Layout.fill }
                                    (Layout.selectableList
                                        { onSelect = identity
                                        , selected = \item -> Tui.text ("▸ " ++ item)
                                        , default = \item -> Tui.text ("  " ++ item)
                                        }
                                        [ "Api", "Core", "Utils", "Main" ]
                                        |> Layout.withFilterable identity [ "Api", "Core", "Utils", "Main" ]
                                    )
                                , Layout.pane "items"
                                    { title = "Items", width = Layout.fill }
                                    (Layout.selectableList
                                        { onSelect = identity
                                        , selected = \item -> Tui.text ("▸ " ++ item)
                                        , default = \item -> Tui.text ("  " ++ item)
                                        }
                                        [ "foo", "bar", "baz", "qux" ]
                                        |> Layout.withFilterable identity [ "foo", "bar", "baz", "qux" ]
                                    )
                                ]

                        state =
                            Layout.init
                                |> Layout.withContext { width = 50, height = 10 }
                                |> Layout.focusPane "items"

                        -- Start filter on items pane, type "ba"
                        ( s1, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Character '/', modifiers = [] }
                                twoFilterablePanes
                                state

                        ( s2, _ ) =
                            "ba"
                                |> String.toList
                                |> List.foldl
                                    (\c ( s, _ ) ->
                                        Layout.handleKeyEvent
                                            { key = Tui.Character c, modifiers = [] }
                                            twoFilterablePanes
                                            s
                                    )
                                    ( s1, False )

                        rendered =
                            twoFilterablePanes
                                |> Layout.toScreen s2
                                |> Tui.toString
                    in
                    Expect.all
                        [ -- Items pane should be filtered: "bar" and "baz" visible, "foo" and "qux" hidden
                          \r -> r |> String.contains "bar" |> Expect.equal True
                        , \r -> r |> String.contains "baz" |> Expect.equal True
                        , \r -> r |> String.contains "foo" |> Expect.equal False
                        , \r -> r |> String.contains "qux" |> Expect.equal False
                        , -- Modules pane should NOT be filtered: all items visible
                          \r -> r |> String.contains "Api" |> Expect.equal True
                        , \r -> r |> String.contains "Core" |> Expect.equal True
                        , \r -> r |> String.contains "Utils" |> Expect.equal True
                        , \r -> r |> String.contains "Main" |> Expect.equal True
                        ]
                        rendered
            ]
        , describe "smart case matching"
            [ test "lowercase query is case-insensitive" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        -- Type "APPLE" — uppercase should be case-sensitive
                        s =
                            startFilterWith "apple" state

                        rendered =
                            filterableList |> Layout.toScreen s |> Tui.toString
                    in
                    rendered |> String.contains "apple" |> Expect.equal True
            ]
        , describe "filter status"
            [ test "filterStatusBar shows filter text while typing" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        s =
                            startFilterWith "ber" state

                        status =
                            Layout.filterStatusBar "fruits" s
                                |> Maybe.map Tui.toString
                    in
                    status |> Expect.equal (Just "Filter: ber")
            , test "filterStatusBar shows applied text after Enter" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        s1 =
                            startFilterWith "ber" state

                        ( s2, _ ) =
                            Layout.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                filterableList
                                s1

                        status =
                            Layout.filterStatusBar "fruits" s2
                                |> Maybe.map Tui.toString
                    in
                    status |> Expect.equal (Just "Filter: matches for 'ber' <esc>: Exit filter mode")
            , test "filterStatusBar returns Nothing when not filtering" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"
                    in
                    Layout.filterStatusBar "fruits" state |> Expect.equal Nothing
            , test "activeFilterStatusBar returns status for whichever pane is filtering" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        s =
                            startFilterWith "ber" state

                        status =
                            Layout.activeFilterStatusBar s
                                |> Maybe.map Tui.toString
                    in
                    status |> Expect.equal (Just "Filter: ber")
            , test "activeFilterStatusBar returns Nothing when not filtering" <|
                \() ->
                    Layout.activeFilterStatusBar Layout.init |> Expect.equal Nothing
            ]
        , describe "space-separated AND matching"
            [ test "two terms both must match" <|
                \() ->
                    let
                        -- "blue berry" should match "blueberry" (both terms present)
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        s =
                            startFilterWith "blue berry" state

                        rendered =
                            filterableList |> Layout.toScreen s |> Tui.toString
                    in
                    Expect.all
                        [ \r -> r |> String.contains "blueberry" |> Expect.equal True
                        , \r -> r |> String.contains "elderberry" |> Expect.equal False
                        , \r -> r |> String.contains "apple" |> Expect.equal False
                        ]
                        rendered
            , test "single term matches normally" <|
                \() ->
                    let
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        s =
                            startFilterWith "berry" state

                        rendered =
                            filterableList |> Layout.toScreen s |> Tui.toString
                    in
                    Expect.all
                        [ \r -> r |> String.contains "blueberry" |> Expect.equal True
                        , \r -> r |> String.contains "elderberry" |> Expect.equal True
                        , \r -> r |> String.contains "apple" |> Expect.equal False
                        ]
                        rendered
            , test "terms with different cases use per-term smart-case" <|
                \() ->
                    let
                        -- "Apple" has uppercase → case-sensitive for that term
                        state =
                            Layout.init
                                |> Layout.withContext { width = 30, height = 12 }
                                |> Layout.focusPane "fruits"

                        s =
                            startFilterWith "Apple" state

                        rendered =
                            filterableList |> Layout.toScreen s |> Tui.toString
                    in
                    -- "apple" should NOT match "Apple" (case-sensitive)
                    rendered |> String.contains "apple" |> Expect.equal False
            ]
        ]


{-| Helper: start a filter and type the given string (custom layout).
-}
startFilterWithLayout : String -> Layout.Layout Int -> Layout.State -> Layout.State
startFilterWithLayout query layout state =
    let
        ( s1, _ ) =
            Layout.handleKeyEvent
                { key = Tui.Character '/', modifiers = [] }
                layout
                state
    in
    query
        |> String.toList
        |> List.foldl
            (\c ( s, _ ) ->
                Layout.handleKeyEvent
                    { key = Tui.Character c, modifiers = [] }
                    layout
                    s
            )
            ( s1, False )
        |> Tuple.first


{-| Helper: start a filter and type the given string.
-}
startFilterWith : String -> Layout.State -> Layout.State
startFilterWith query state =
    let
        ( s1, _ ) =
            Layout.handleKeyEvent
                { key = Tui.Character '/', modifiers = [] }
                filterableList
                state
    in
    query
        |> String.toList
        |> List.foldl
            (\c ( s, _ ) ->
                Layout.handleKeyEvent
                    { key = Tui.Character c, modifiers = [] }
                    filterableList
                    s
            )
            ( s1, False )
        |> Tuple.first
