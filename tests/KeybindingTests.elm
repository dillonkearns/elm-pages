module KeybindingTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Event
import Tui.Keybinding as Keybinding
import Tui.Screen


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
        [ Keybinding.binding (Tui.Event.Character 'q') "Quit" Quit
        , Keybinding.binding (Tui.Event.Character '?') "Help" Help
        , Keybinding.binding Tui.Event.Tab "Switch pane" SwitchPane
        , Keybinding.binding (Tui.Event.Character 'c') "Commit" Commit
        ]


sampleCommits : Keybinding.Group Action
sampleCommits =
    Keybinding.group "Commits"
        [ Keybinding.binding (Tui.Event.Character 'j') "Next commit" NavigateDown
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)
        , Keybinding.binding (Tui.Event.Character 'k') "Previous commit" NavigateUp
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Up)
        ]


sampleDiff : Keybinding.Group Action
sampleDiff =
    Keybinding.group "Diff"
        [ Keybinding.binding (Tui.Event.Character 'j') "Scroll down" ScrollDown
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)
        , Keybinding.binding (Tui.Event.Character 'k') "Scroll up" ScrollUp
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Up)
        ]


suite : Test
suite =
    describe "Tui.Keybinding"
        [ describe "dispatch"
            [ test "matches a simple binding" <|
                \() ->
                    Keybinding.dispatch [ sampleGlobal ]
                        { key = Tui.Event.Character 'q', modifiers = [] }
                        |> Expect.equal (Just Quit)
            , test "matches alternate key" <|
                \() ->
                    Keybinding.dispatch [ sampleCommits ]
                        { key = Tui.Event.Arrow Tui.Event.Down, modifiers = [] }
                        |> Expect.equal (Just NavigateDown)
            , test "returns Nothing when no match" <|
                \() ->
                    Keybinding.dispatch [ sampleGlobal ]
                        { key = Tui.Event.Character 'z', modifiers = [] }
                        |> Expect.equal Nothing
            , test "tries groups in order — first match wins" <|
                \() ->
                    -- 'j' means NavigateDown in commits but ScrollDown in diff
                    -- commits group listed first, so NavigateDown wins
                    Keybinding.dispatch [ sampleCommits, sampleDiff ]
                        { key = Tui.Event.Character 'j', modifiers = [] }
                        |> Expect.equal (Just NavigateDown)
            , test "falls through to later group" <|
                \() ->
                    -- 'q' not in commits, falls through to global
                    Keybinding.dispatch [ sampleCommits, sampleGlobal ]
                        { key = Tui.Event.Character 'q', modifiers = [] }
                        |> Expect.equal (Just Quit)
            , test "matches binding with modifiers" <|
                \() ->
                    let
                        groups : List (Keybinding.Group Action)
                        groups =
                            [ Keybinding.group "Test"
                                [ Keybinding.withModifiers [ Tui.Event.Ctrl ]
                                    (Tui.Event.Character 's')
                                    "Save"
                                    Commit
                                ]
                            ]
                    in
                    Keybinding.dispatch groups
                        { key = Tui.Event.Character 's', modifiers = [ Tui.Event.Ctrl ] }
                        |> Expect.equal (Just Commit)
            , test "modifier mismatch does not match" <|
                \() ->
                    let
                        groups : List (Keybinding.Group Action)
                        groups =
                            [ Keybinding.group "Test"
                                [ Keybinding.withModifiers [ Tui.Event.Ctrl ]
                                    (Tui.Event.Character 's')
                                    "Save"
                                    Commit
                                ]
                            ]
                    in
                    Keybinding.dispatch groups
                        { key = Tui.Event.Character 's', modifiers = [] }
                        |> Expect.equal Nothing
            ]
        , describe "formatKey"
            [ test "formats character key" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.Character 'j') []
                        |> Expect.equal "j"
            , test "formats uppercase character" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.Character 'J') []
                        |> Expect.equal "J"
            , test "formats space as 'space'" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.Character ' ') []
                        |> Expect.equal "space"
            , test "formats arrow up as ↑" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.Arrow Tui.Event.Up) []
                        |> Expect.equal "↑"
            , test "formats arrow down as ↓" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.Arrow Tui.Event.Down) []
                        |> Expect.equal "↓"
            , test "formats enter" <|
                \() ->
                    Keybinding.formatKey Tui.Event.Enter []
                        |> Expect.equal "enter"
            , test "formats escape" <|
                \() ->
                    Keybinding.formatKey Tui.Event.Escape []
                        |> Expect.equal "esc"
            , test "formats tab" <|
                \() ->
                    Keybinding.formatKey Tui.Event.Tab []
                        |> Expect.equal "tab"
            , test "formats function key" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.FunctionKey 1) []
                        |> Expect.equal "F1"
            , test "formats ctrl modifier" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.Character 'a') [ Tui.Event.Ctrl ]
                        |> Expect.equal "ctrl+a"
            , test "formats alt modifier" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.Character 'x') [ Tui.Event.Alt ]
                        |> Expect.equal "alt+x"
            , test "formats multiple modifiers" <|
                \() ->
                    Keybinding.formatKey (Tui.Event.Character 's') [ Tui.Event.Ctrl, Tui.Event.Shift ]
                        |> Expect.equal "ctrl+shift+s"
            ]
        , describe "formatBinding"
            [ test "formats single key binding" <|
                \() ->
                    Keybinding.binding (Tui.Event.Character 'q') "Quit" Quit
                        |> Keybinding.formatBinding
                        |> Expect.equal "q"
            , test "formats binding with alternate key" <|
                \() ->
                    Keybinding.binding (Tui.Event.Character 'j') "Next" NavigateDown
                        |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)
                        |> Keybinding.formatBinding
                        |> Expect.equal "j/↓"
            , test "formats binding with modifier" <|
                \() ->
                    Keybinding.withModifiers [ Tui.Event.Ctrl ] (Tui.Event.Character 'c') "Copy" Commit
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
