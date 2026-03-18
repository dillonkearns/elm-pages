module OptionsBarTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Keybinding as Keybinding
import Tui.OptionsBar as OptionsBar


sampleBindings : List (Keybinding.Group action)
sampleBindings =
    [ Keybinding.group "Local"
        [ Keybinding.binding (Tui.Character 'j') "Next" ()
            |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
        , Keybinding.binding (Tui.Character 'k') "Previous" ()
        ]
    , Keybinding.group "Global"
        [ Keybinding.binding (Tui.Character 'q') "Quit" ()
        , Keybinding.binding (Tui.Character '?') "Help" ()
        , Keybinding.binding (Tui.Character 'c') "Commit" ()
        ]
    ]


suite : Test
suite =
    describe "Tui.OptionsBar"
        [ test "shows binding descriptions and keys" <|
            \() ->
                OptionsBar.view 80 sampleBindings
                    |> Tui.toString
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
                    |> Tui.toString
                    |> String.contains "|"
                    |> Expect.equal True
        , test "truncates with ... when too narrow" <|
            \() ->
                OptionsBar.view 30 sampleBindings
                    |> Tui.toString
                    |> String.contains "…"
                    |> Expect.equal True
        , test "empty bindings returns empty" <|
            \() ->
                OptionsBar.view 80 []
                    |> Tui.toString
                    |> Expect.equal ""
        , test "uses short format: description: key" <|
            \() ->
                OptionsBar.view 80 sampleBindings
                    |> Tui.toString
                    |> String.contains "Next: j"
                    |> Expect.equal True
        ]
