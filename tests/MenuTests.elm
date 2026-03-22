module MenuTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Menu as Menu


sampleMenu : Menu.State String
sampleMenu =
    Menu.open
        [ Menu.section "Files"
            [ Menu.item { key = Tui.Character 's', label = "Stage", action = "stage" }
            , Menu.item { key = Tui.Character 'd', label = "Discard", action = "discard" }
            , Menu.disabledItem { key = Tui.Character 'u', label = "Unstage", reason = "Nothing staged" }
            ]
        , Menu.section "Commit"
            [ Menu.item { key = Tui.Character 'c', label = "Commit", action = "commit" }
            , Menu.item { key = Tui.Character 'a', label = "Amend", action = "amend" }
            ]
        ]


suite : Test
suite =
    describe "Tui.Menu"
        [ describe "direct key dispatch"
            [ test "pressing a bound key fires the action immediately" <|
                \() ->
                    let
                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'c', modifiers = [] }
                                sampleMenu
                    in
                    maybeAction |> Expect.equal (Just "commit")
            , test "pressing another bound key fires that action" <|
                \() ->
                    let
                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 's', modifiers = [] }
                                sampleMenu
                    in
                    maybeAction |> Expect.equal (Just "stage")
            , test "pressing a disabled item's key does not fire" <|
                \() ->
                    let
                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'u', modifiers = [] }
                                sampleMenu
                    in
                    maybeAction |> Expect.equal Nothing
            , test "pressing an unbound key does nothing" <|
                \() ->
                    let
                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'z', modifiers = [] }
                                sampleMenu
                    in
                    maybeAction |> Expect.equal Nothing
            ]
        , describe "j/k navigation"
            [ test "j moves selection down" <|
                \() ->
                    let
                        ( state, _ ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'j', modifiers = [] }
                                sampleMenu

                        -- Enter selects the highlighted item
                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                state
                    in
                    -- First item is "Stage", j moves to "Discard"
                    maybeAction |> Expect.equal (Just "discard")
            , test "k moves selection up" <|
                \() ->
                    let
                        -- Move down twice, then up once
                        ( s1, _ ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'j', modifiers = [] }
                                sampleMenu

                        ( s2, _ ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'j', modifiers = [] }
                                s1

                        ( s3, _ ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'k', modifiers = [] }
                                s2

                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                s3
                    in
                    maybeAction |> Expect.equal (Just "discard")
            , test "j skips disabled items" <|
                \() ->
                    let
                        -- Move down twice: Stage → Discard → (skip Unstage) → Commit
                        ( s1, _ ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'j', modifiers = [] }
                                sampleMenu

                        ( s2, _ ) =
                            Menu.handleKeyEvent
                                { key = Tui.Character 'j', modifiers = [] }
                                s1

                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                s2
                    in
                    maybeAction |> Expect.equal (Just "commit")
            , test "Enter on highlighted item fires action" <|
                \() ->
                    let
                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Enter, modifiers = [] }
                                sampleMenu
                    in
                    -- First enabled item is "Stage"
                    maybeAction |> Expect.equal (Just "stage")
            ]
        , describe "rendering"
            [ test "viewBody shows section headers" <|
                \() ->
                    let
                        rendered =
                            Menu.viewBody sampleMenu
                                |> List.map Tui.toString
                                |> String.join "\n"
                    in
                    Expect.all
                        [ \r -> r |> String.contains "Files" |> Expect.equal True
                        , \r -> r |> String.contains "Commit" |> Expect.equal True
                        ]
                        rendered
            , test "viewBody shows item labels with keys" <|
                \() ->
                    let
                        rendered =
                            Menu.viewBody sampleMenu
                                |> List.map Tui.toString
                                |> String.join "\n"
                    in
                    Expect.all
                        [ \r -> r |> String.contains "Stage" |> Expect.equal True
                        , \r -> r |> String.contains "Discard" |> Expect.equal True
                        , \r -> r |> String.contains "Commit" |> Expect.equal True
                        , \r -> r |> String.contains "s" |> Expect.equal True
                        ]
                        rendered
            , test "viewBody shows disabled items with reason" <|
                \() ->
                    let
                        rendered =
                            Menu.viewBody sampleMenu
                                |> List.map Tui.toString
                                |> String.join "\n"
                    in
                    Expect.all
                        [ \r -> r |> String.contains "Unstage" |> Expect.equal True
                        , \r -> r |> String.contains "Nothing staged" |> Expect.equal True
                        ]
                        rendered
            , test "title returns Menu" <|
                \() ->
                    Menu.title |> Expect.equal "Menu"
            ]
        , describe "Escape"
            [ test "Escape returns Nothing (caller dismisses)" <|
                \() ->
                    let
                        ( _, maybeAction ) =
                            Menu.handleKeyEvent
                                { key = Tui.Escape, modifiers = [] }
                                sampleMenu
                    in
                    maybeAction |> Expect.equal Nothing
            ]
        ]
