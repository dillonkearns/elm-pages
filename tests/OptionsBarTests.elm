module OptionsBarTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Event
import Tui.Keybinding as Keybinding
import Tui.OptionsBar as OptionsBar
import Tui.Screen


sampleBindings : List (Keybinding.Group action)
sampleBindings =
    [ Keybinding.group "Local"
        [ Keybinding.binding (Tui.Event.Character 'j') "Next" ()
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)
        , Keybinding.binding (Tui.Event.Character 'k') "Previous" ()
        ]
    , Keybinding.group "Global"
        [ Keybinding.binding (Tui.Event.Character 'q') "Quit" ()
        , Keybinding.binding (Tui.Event.Character '?') "Help" ()
        , Keybinding.binding (Tui.Event.Character 'c') "Commit" ()
        ]
    ]


suite : Test
suite =
    describe "Tui.OptionsBar"
        [ test "shows binding descriptions and keys" <|
            \() ->
                OptionsBar.view 80 sampleBindings
                    |> Tui.Screen.toString
                    |> (\s ->
                            Expect.all
                                [ \str -> str |> String.contains "Next" |> Expect.equal True
                                , \str -> str |> String.contains "j" |> Expect.equal True
                                , \str -> str |> String.contains "Quit" |> Expect.equal True
                                , \str -> str |> String.contains "q" |> Expect.equal True
                                ]
                                s
                       )
        , test "separates items with |" <|
            \() ->
                OptionsBar.view 80 sampleBindings
                    |> Tui.Screen.toString
                    |> String.contains "|"
                    |> Expect.equal True
        , test "truncates with ... when too narrow" <|
            \() ->
                OptionsBar.view 30 sampleBindings
                    |> Tui.Screen.toString
                    |> String.contains "…"
                    |> Expect.equal True
        , test "empty bindings returns empty" <|
            \() ->
                OptionsBar.view 80 []
                    |> Tui.Screen.toString
                    |> Expect.equal ""
        , test "uses short format: description: key" <|
            \() ->
                OptionsBar.view 80 sampleBindings
                    |> Tui.Screen.toString
                    |> String.contains "Next: j"
                    |> Expect.equal True
        ]
