module PickerTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Picker as Picker


suite : Test
suite =
    describe "Tui.Picker"
        [ describe "viewBodyWithMaxRows"
            [ test "keeps the selected item visible in long pickers" <|
                \() ->
                    longPicker
                        |> navigateDownN 8
                        |> Picker.viewBodyWithMaxRows 7
                        |> Tui.lines
                        |> Tui.toString
                        |> expectContains "Item 09"
            , test "keeps the rendered row count stable when scrolled near the end" <|
                \() ->
                    longPicker
                        |> navigateDownN 11
                        |> Picker.viewBodyWithMaxRows 7
                        |> List.length
                        |> Expect.equal 7
            ]
        ]


longPicker : Picker.State String
longPicker =
    Picker.open
        { items =
            List.range 1 12
                |> List.map (\i -> "Item " ++ String.padLeft 2 '0' (String.fromInt i))
        , toString = identity
        , title = "Pick item"
        }


navigateDownN : Int -> Picker.State item -> Picker.State item
navigateDownN count state =
    if count <= 0 then
        state

    else
        navigateDownN (count - 1) (Picker.navigateDown state)


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
