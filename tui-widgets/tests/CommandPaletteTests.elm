module CommandPaletteTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.CommandPalette as CommandPalette
import Tui.Keybinding as Keybinding


suite : Test
suite =
    describe "Tui.CommandPalette"
        [ describe "viewBodyWithMaxRows"
            [ test "keeps the selected action visible in long palettes" <|
                \() ->
                    longPalette
                        |> navigateDownN 8
                        |> CommandPalette.viewBodyWithMaxRows 7
                        |> Tui.lines
                        |> Tui.toString
                        |> expectContains "Action 09"
            , test "keeps the rendered row count stable when scrolled near the end" <|
                \() ->
                    longPalette
                        |> navigateDownN 11
                        |> CommandPalette.viewBodyWithMaxRows 7
                        |> List.length
                        |> Expect.equal 7
            ]
        ]


longPalette : CommandPalette.State String
longPalette =
    CommandPalette.open
        [ Keybinding.group "Actions"
            (List.range 1 12
                |> List.map
                    (\i ->
                        let
                            label =
                                "Action " ++ String.padLeft 2 '0' (String.fromInt i)

                            keyChar =
                                Char.fromCode (Char.toCode 'a' + i - 1)
                        in
                        Keybinding.binding (Tui.Character keyChar) label label
                    )
            )
        ]


navigateDownN : Int -> CommandPalette.State action -> CommandPalette.State action
navigateDownN count state =
    if count <= 0 then
        state

    else
        navigateDownN (count - 1) (CommandPalette.navigateDown state)


expectContains : String -> String -> Expect.Expectation
expectContains needle haystack =
    if String.contains needle haystack then
        Expect.pass

    else
        Expect.fail
            ("Expected to find \""
                ++ needle
                ++ "\" in:\n\n"
                ++ haystack
            )
