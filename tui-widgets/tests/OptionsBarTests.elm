module OptionsBarTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Event
import Tui.Keybinding as Keybinding
import Tui.OptionsBar as OptionsBar
import Tui.Screen


suite : Test
suite =
    describe "Tui.OptionsBar"
        [ test "renders alternate keys and modifiers in the bar" <|
            \() ->
                sampleBindings
                    |> OptionsBar.view 80
                    |> Tui.Screen.toString
                    |> Expect.equal "Next: j/↓ | Save: ctrl+s"
        , test "truncates predictably after richer key labels" <|
            \() ->
                sampleBindings
                    |> OptionsBar.view 13
                    |> Tui.Screen.toString
                    |> Expect.equal "Next: j/↓ | …"
        , test "shows an ellipsis when the first entry does not fit" <|
            \() ->
                sampleBindings
                    |> OptionsBar.view 1
                    |> Tui.Screen.toString
                    |> Expect.equal "…"
        ]


sampleBindings : List (Keybinding.Group ())
sampleBindings =
    [ Keybinding.group "Actions"
        [ Keybinding.binding (Tui.Event.Character 'j') "Next" ()
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)
        , Keybinding.withModifiers [ Tui.Event.Ctrl ] (Tui.Event.Character 's') "Save" ()
        ]
    ]
