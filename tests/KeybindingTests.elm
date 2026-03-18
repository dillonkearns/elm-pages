module KeybindingTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Keybinding as Keybinding


{-| Test action type — simple enum for keybinding dispatch tests.
-}
type Action
    = NavigateUp
    | NavigateDown
    | Quit
    | Commit
    | Help
    | SwitchPane
    | ScrollUp
    | ScrollDown


sampleGlobal : Keybinding.Group Action
sampleGlobal =
    Keybinding.group "Global"
        [ Keybinding.binding (Tui.Character 'q') "Quit" Quit
        , Keybinding.binding (Tui.Character '?') "Help" Help
        , Keybinding.binding Tui.Tab "Switch pane" SwitchPane
        , Keybinding.binding (Tui.Character 'c') "Commit" Commit
        ]


sampleCommits : Keybinding.Group Action
sampleCommits =
    Keybinding.group "Commits"
        [ Keybinding.binding (Tui.Character 'j') "Next commit" NavigateDown
            |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
        , Keybinding.binding (Tui.Character 'k') "Previous commit" NavigateUp
            |> Keybinding.withAlternate (Tui.Arrow Tui.Up)
        ]


sampleDiff : Keybinding.Group Action
sampleDiff =
    Keybinding.group "Diff"
        [ Keybinding.binding (Tui.Character 'j') "Scroll down" ScrollDown
            |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
        , Keybinding.binding (Tui.Character 'k') "Scroll up" ScrollUp
            |> Keybinding.withAlternate (Tui.Arrow Tui.Up)
        ]


suite : Test
suite =
    describe "Tui.Keybinding"
        [ describe "dispatch"
            [ test "matches a simple binding" <|
                \() ->
                    Keybinding.dispatch [ sampleGlobal ]
                        { key = Tui.Character 'q', modifiers = [] }
                        |> Expect.equal (Just Quit)
            , test "matches alternate key" <|
                \() ->
                    Keybinding.dispatch [ sampleCommits ]
                        { key = Tui.Arrow Tui.Down, modifiers = [] }
                        |> Expect.equal (Just NavigateDown)
            , test "returns Nothing when no match" <|
                \() ->
                    Keybinding.dispatch [ sampleGlobal ]
                        { key = Tui.Character 'z', modifiers = [] }
                        |> Expect.equal Nothing
            , test "tries groups in order — first match wins" <|
                \() ->
                    -- 'j' means NavigateDown in commits but ScrollDown in diff
                    -- commits group listed first, so NavigateDown wins
                    Keybinding.dispatch [ sampleCommits, sampleDiff ]
                        { key = Tui.Character 'j', modifiers = [] }
                        |> Expect.equal (Just NavigateDown)
            , test "falls through to later group" <|
                \() ->
                    -- 'q' not in commits, falls through to global
                    Keybinding.dispatch [ sampleCommits, sampleGlobal ]
                        { key = Tui.Character 'q', modifiers = [] }
                        |> Expect.equal (Just Quit)
            , test "matches binding with modifiers" <|
                \() ->
                    let
                        groups =
                            [ Keybinding.group "Test"
                                [ Keybinding.withModifiers [ Tui.Ctrl ]
                                    (Tui.Character 's')
                                    "Save"
                                    Commit
                                ]
                            ]
                    in
                    Keybinding.dispatch groups
                        { key = Tui.Character 's', modifiers = [ Tui.Ctrl ] }
                        |> Expect.equal (Just Commit)
            , test "modifier mismatch does not match" <|
                \() ->
                    let
                        groups =
                            [ Keybinding.group "Test"
                                [ Keybinding.withModifiers [ Tui.Ctrl ]
                                    (Tui.Character 's')
                                    "Save"
                                    Commit
                                ]
                            ]
                    in
                    Keybinding.dispatch groups
                        { key = Tui.Character 's', modifiers = [] }
                        |> Expect.equal Nothing
            ]
        , describe "formatKey"
            [ test "formats character key" <|
                \() ->
                    Keybinding.formatKey (Tui.Character 'j') []
                        |> Expect.equal "j"
            , test "formats uppercase character" <|
                \() ->
                    Keybinding.formatKey (Tui.Character 'J') []
                        |> Expect.equal "J"
            , test "formats space as 'space'" <|
                \() ->
                    Keybinding.formatKey (Tui.Character ' ') []
                        |> Expect.equal "space"
            , test "formats arrow up as ↑" <|
                \() ->
                    Keybinding.formatKey (Tui.Arrow Tui.Up) []
                        |> Expect.equal "↑"
            , test "formats arrow down as ↓" <|
                \() ->
                    Keybinding.formatKey (Tui.Arrow Tui.Down) []
                        |> Expect.equal "↓"
            , test "formats enter" <|
                \() ->
                    Keybinding.formatKey Tui.Enter []
                        |> Expect.equal "enter"
            , test "formats escape" <|
                \() ->
                    Keybinding.formatKey Tui.Escape []
                        |> Expect.equal "esc"
            , test "formats tab" <|
                \() ->
                    Keybinding.formatKey Tui.Tab []
                        |> Expect.equal "tab"
            , test "formats function key" <|
                \() ->
                    Keybinding.formatKey (Tui.FunctionKey 1) []
                        |> Expect.equal "F1"
            , test "formats ctrl modifier" <|
                \() ->
                    Keybinding.formatKey (Tui.Character 'a') [ Tui.Ctrl ]
                        |> Expect.equal "ctrl+a"
            , test "formats alt modifier" <|
                \() ->
                    Keybinding.formatKey (Tui.Character 'x') [ Tui.Alt ]
                        |> Expect.equal "alt+x"
            , test "formats multiple modifiers" <|
                \() ->
                    Keybinding.formatKey (Tui.Character 's') [ Tui.Ctrl, Tui.Shift ]
                        |> Expect.equal "ctrl+shift+s"
            ]
        , describe "formatBinding"
            [ test "formats single key binding" <|
                \() ->
                    Keybinding.binding (Tui.Character 'q') "Quit" Quit
                        |> Keybinding.formatBinding
                        |> Expect.equal "q"
            , test "formats binding with alternate key" <|
                \() ->
                    Keybinding.binding (Tui.Character 'j') "Next" NavigateDown
                        |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
                        |> Keybinding.formatBinding
                        |> Expect.equal "j/↓"
            , test "formats binding with modifier" <|
                \() ->
                    Keybinding.withModifiers [ Tui.Ctrl ] (Tui.Character 'c') "Copy" Commit
                        |> Keybinding.formatBinding
                        |> Expect.equal "ctrl+c"
            ]
        , describe "helpRows"
            [ test "generates section headers when not filtering" <|
                \() ->
                    Keybinding.helpRows "" [ sampleCommits, sampleGlobal ]
                        |> List.map Tui.toString
                        |> List.filter (String.contains "---")
                        |> Expect.equal
                            [ "--- Commits ---"
                            , "--- Global ---"
                            ]
            , test "shows key labels and descriptions" <|
                \() ->
                    let
                        rows =
                            Keybinding.helpRows "" [ sampleGlobal ]
                                |> List.map Tui.toString
                    in
                    Expect.all
                        [ \r -> r |> List.any (String.contains "q") |> Expect.equal True
                        , \r -> r |> List.any (String.contains "Quit") |> Expect.equal True
                        , \r -> r |> List.any (String.contains "?") |> Expect.equal True
                        , \r -> r |> List.any (String.contains "Help") |> Expect.equal True
                        ]
                        rows
            , test "shows alternate keys with /" <|
                \() ->
                    Keybinding.helpRows "" [ sampleCommits ]
                        |> List.map Tui.toString
                        |> List.any (String.contains "j/↓")
                        |> Expect.equal True
            , test "filters by description" <|
                \() ->
                    let
                        rows =
                            Keybinding.helpRows "quit" [ sampleGlobal ]
                                |> List.map Tui.toString
                    in
                    Expect.all
                        [ \r -> r |> List.any (String.contains "Quit") |> Expect.equal True
                        , \r -> r |> List.any (String.contains "Help") |> Expect.equal False
                        , \r -> r |> List.any (String.contains "Commit") |> Expect.equal False
                        ]
                        rows
            , test "filters by key with @ prefix" <|
                \() ->
                    let
                        rows =
                            Keybinding.helpRows "@tab" [ sampleGlobal ]
                                |> List.map Tui.toString
                    in
                    Expect.all
                        [ \r -> r |> List.any (String.contains "Switch pane") |> Expect.equal True
                        , \r -> r |> List.any (String.contains "Quit") |> Expect.equal False
                        ]
                        rows
            , test "hides section headers when filtering" <|
                \() ->
                    Keybinding.helpRows "quit" [ sampleCommits, sampleGlobal ]
                        |> List.map Tui.toString
                        |> List.filter (String.contains "---")
                        |> Expect.equal []
            , test "case-insensitive description filtering" <|
                \() ->
                    Keybinding.helpRows "QUIT" [ sampleGlobal ]
                        |> List.map Tui.toString
                        |> List.any (String.contains "Quit")
                        |> Expect.equal True
            , test "case-insensitive key filtering" <|
                \() ->
                    Keybinding.helpRows "@TAB" [ sampleGlobal ]
                        |> List.map Tui.toString
                        |> List.any (String.contains "Switch pane")
                        |> Expect.equal True
            , test "empty groups are excluded" <|
                \() ->
                    Keybinding.helpRows "quit" [ sampleCommits, sampleGlobal ]
                        |> List.map Tui.toString
                        |> List.filter (String.contains "Commits")
                        |> Expect.equal []
            , test "blank line separates groups" <|
                \() ->
                    let
                        rows =
                            Keybinding.helpRows "" [ sampleCommits, sampleGlobal ]
                                |> List.map Tui.toString

                        blankLines =
                            rows |> List.filter (\r -> String.trim r == "")
                    in
                    -- At least one blank separator between the two groups
                    List.length blankLines
                        |> Expect.atLeast 1
            ]
        ]
