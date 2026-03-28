module OptionsBarTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Keybinding as Keybinding
import Tui.OptionsBar as OptionsBar


suite : Test
suite =
    describe "Tui.OptionsBar"
        [ test "renders alternate keys and modifiers in the bar" <|
            \() ->
                sampleBindings
                    |> OptionsBar.view 80
                    |> Tui.toString
                    |> Expect.equal "Next: j/↓ | Save: ctrl+s"
        , test "truncates predictably after richer key labels" <|
            \() ->
                sampleBindings
                    |> OptionsBar.view 13
                    |> Tui.toString
                    |> Expect.equal "Next: j/↓ | …"
        , test "shows an ellipsis when the first entry does not fit" <|
            \() ->
                sampleBindings
                    |> OptionsBar.view 1
                    |> Tui.toString
                    |> Expect.equal "…"
        ]


sampleBindings : List (Keybinding.Group ())
sampleBindings =
    [ Keybinding.group "Actions"
        [ Keybinding.binding (Tui.Character 'j') "Next" ()
            |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
        , Keybinding.withModifiers [ Tui.Ctrl ] (Tui.Character 's') "Save" ()
        ]
    ]
