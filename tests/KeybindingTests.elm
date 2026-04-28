module KeybindingTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui.Keybinding as Keybinding
import Tui.Screen
import Tui.Sub


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
        [ Keybinding.binding (Tui.Sub.Character 'q') "Quit" Quit
        , Keybinding.binding (Tui.Sub.Character '?') "Help" Help
        , Keybinding.binding Tui.Sub.Tab "Switch pane" SwitchPane
        , Keybinding.binding (Tui.Sub.Character 'c') "Commit" Commit
        ]


sampleCommits : Keybinding.Group Action
sampleCommits =
    Keybinding.group "Commits"
        [ Keybinding.binding (Tui.Sub.Character 'j') "Next commit" NavigateDown
            |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Down)
        , Keybinding.binding (Tui.Sub.Character 'k') "Previous commit" NavigateUp
            |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Up)
        ]


sampleDiff : Keybinding.Group Action
sampleDiff =
    Keybinding.group "Diff"
        [ Keybinding.binding (Tui.Sub.Character 'j') "Scroll down" ScrollDown
            |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Down)
        , Keybinding.binding (Tui.Sub.Character 'k') "Scroll up" ScrollUp
            |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Up)
        ]


suite : Test
suite =
    describe "Tui.Keybinding"
        [ describe "dispatch"
            [ test "matches a simple binding" <|
                \() ->
                    Keybinding.dispatch [ sampleGlobal ]
                        { key = Tui.Sub.Character 'q', modifiers = [] }
                        |> Expect.equal (Just Quit)
            , test "matches alternate key" <|
                \() ->
                    Keybinding.dispatch [ sampleCommits ]
                        { key = Tui.Sub.Arrow Tui.Sub.Down, modifiers = [] }
                        |> Expect.equal (Just NavigateDown)
            , test "returns Nothing when no match" <|
                \() ->
                    Keybinding.dispatch [ sampleGlobal ]
                        { key = Tui.Sub.Character 'z', modifiers = [] }
                        |> Expect.equal Nothing
            , test "tries groups in order — first match wins" <|
                \() ->
                    -- 'j' means NavigateDown in commits but ScrollDown in diff
                    -- commits group listed first, so NavigateDown wins
                    Keybinding.dispatch [ sampleCommits, sampleDiff ]
                        { key = Tui.Sub.Character 'j', modifiers = [] }
                        |> Expect.equal (Just NavigateDown)
            , test "falls through to later group" <|
                \() ->
                    -- 'q' not in commits, falls through to global
                    Keybinding.dispatch [ sampleCommits, sampleGlobal ]
                        { key = Tui.Sub.Character 'q', modifiers = [] }
                        |> Expect.equal (Just Quit)
            , test "matches binding with modifiers" <|
                \() ->
                    let
                        groups : List (Keybinding.Group Action)
                        groups =
                            [ Keybinding.group "Test"
                                [ Keybinding.withModifiers [ Tui.Sub.Ctrl ]
                                    (Tui.Sub.Character 's')
                                    "Save"
                                    Commit
                                ]
                            ]
                    in
                    Keybinding.dispatch groups
                        { key = Tui.Sub.Character 's', modifiers = [ Tui.Sub.Ctrl ] }
                        |> Expect.equal (Just Commit)
            , test "modifier mismatch does not match" <|
                \() ->
                    let
                        groups : List (Keybinding.Group Action)
                        groups =
                            [ Keybinding.group "Test"
                                [ Keybinding.withModifiers [ Tui.Sub.Ctrl ]
                                    (Tui.Sub.Character 's')
                                    "Save"
                                    Commit
                                ]
                            ]
                    in
                    Keybinding.dispatch groups
                        { key = Tui.Sub.Character 's', modifiers = [] }
                        |> Expect.equal Nothing
            ]
        , describe "formatKey"
            [ test "formats character key" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.Character 'j') []
                        |> Expect.equal "j"
            , test "formats uppercase character" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.Character 'J') []
                        |> Expect.equal "J"
            , test "formats space as 'space'" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.Character ' ') []
                        |> Expect.equal "space"
            , test "formats arrow up as ↑" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.Arrow Tui.Sub.Up) []
                        |> Expect.equal "↑"
            , test "formats arrow down as ↓" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.Arrow Tui.Sub.Down) []
                        |> Expect.equal "↓"
            , test "formats enter" <|
                \() ->
                    Keybinding.formatKey Tui.Sub.Enter []
                        |> Expect.equal "enter"
            , test "formats escape" <|
                \() ->
                    Keybinding.formatKey Tui.Sub.Escape []
                        |> Expect.equal "esc"
            , test "formats tab" <|
                \() ->
                    Keybinding.formatKey Tui.Sub.Tab []
                        |> Expect.equal "tab"
            , test "formats function key" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.FunctionKey 1) []
                        |> Expect.equal "F1"
            , test "formats ctrl modifier" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.Character 'a') [ Tui.Sub.Ctrl ]
                        |> Expect.equal "ctrl+a"
            , test "formats alt modifier" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.Character 'x') [ Tui.Sub.Alt ]
                        |> Expect.equal "alt+x"
            , test "formats multiple modifiers" <|
                \() ->
                    Keybinding.formatKey (Tui.Sub.Character 's') [ Tui.Sub.Ctrl, Tui.Sub.Shift ]
                        |> Expect.equal "ctrl+shift+s"
            ]
        , describe "formatBinding"
            [ test "formats single key binding" <|
                \() ->
                    Keybinding.binding (Tui.Sub.Character 'q') "Quit" Quit
                        |> Keybinding.formatBinding
                        |> Expect.equal "q"
            , test "formats binding with alternate key" <|
                \() ->
                    Keybinding.binding (Tui.Sub.Character 'j') "Next" NavigateDown
                        |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Down)
                        |> Keybinding.formatBinding
                        |> Expect.equal "j/↓"
            , test "formats binding with modifier" <|
                \() ->
                    Keybinding.withModifiers [ Tui.Sub.Ctrl ] (Tui.Sub.Character 'c') "Copy" Commit
                        |> Keybinding.formatBinding
                        |> Expect.equal "ctrl+c"
            ]
        , describe "helpRows"
            [ test "generates section headers when not filtering" <|
                \() ->
                    Keybinding.helpRows "" [ sampleCommits, sampleGlobal ]
                        |> List.map Tui.Screen.toString
                        |> List.filter (String.contains "---")
                        |> Expect.equal
                            [ "--- Commits ---"
                            , "--- Global ---"
                            ]
            , test "shows key labels and descriptions" <|
                \() ->
                    let
                        rows : List String
                        rows =
                            Keybinding.helpRows "" [ sampleGlobal ]
                                |> List.map Tui.Screen.toString
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
                        |> List.map Tui.Screen.toString
                        |> List.any (String.contains "j/↓")
                        |> Expect.equal True
            , test "filters by description" <|
                \() ->
                    let
                        rows : List String
                        rows =
                            Keybinding.helpRows "quit" [ sampleGlobal ]
                                |> List.map Tui.Screen.toString
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
                        rows : List String
                        rows =
                            Keybinding.helpRows "@tab" [ sampleGlobal ]
                                |> List.map Tui.Screen.toString
                    in
                    Expect.all
                        [ \r -> r |> List.any (String.contains "Switch pane") |> Expect.equal True
                        , \r -> r |> List.any (String.contains "Quit") |> Expect.equal False
                        ]
                        rows
            , test "hides section headers when filtering" <|
                \() ->
                    Keybinding.helpRows "quit" [ sampleCommits, sampleGlobal ]
                        |> List.map Tui.Screen.toString
                        |> List.filter (String.contains "---")
                        |> Expect.equal []
            , test "case-insensitive description filtering" <|
                \() ->
                    Keybinding.helpRows "QUIT" [ sampleGlobal ]
                        |> List.map Tui.Screen.toString
                        |> List.any (String.contains "Quit")
                        |> Expect.equal True
            , test "case-insensitive key filtering" <|
                \() ->
                    Keybinding.helpRows "@TAB" [ sampleGlobal ]
                        |> List.map Tui.Screen.toString
                        |> List.any (String.contains "Switch pane")
                        |> Expect.equal True
            , test "empty groups are excluded" <|
                \() ->
                    Keybinding.helpRows "quit" [ sampleCommits, sampleGlobal ]
                        |> List.map Tui.Screen.toString
                        |> List.filter (String.contains "Commits")
                        |> Expect.equal []
            , test "blank line separates groups" <|
                \() ->
                    let
                        rows : List String
                        rows =
                            Keybinding.helpRows "" [ sampleCommits, sampleGlobal ]
                                |> List.map Tui.Screen.toString

                        blankLines : List String
                        blankLines =
                            rows |> List.filter (\r -> String.trim r == "")
                    in
                    -- At least one blank separator between the two groups
                    List.length blankLines
                        |> Expect.atLeast 1
            ]
        ]
