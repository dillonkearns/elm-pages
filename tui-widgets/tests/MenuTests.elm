module MenuTests exposing (suite)

import Ansi.Color
import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Menu as Menu
import Tui.Modal as Modal
import Tui.Screen
import Tui.Sub


suite : Test
suite =
    describe "Tui.Menu"
        [ describe "viewBodyWithMaxRows"
            [ test "keeps the highlighted item visible in long menus" <|
                \() ->
                    longMenu
                        |> navigateDownN 8
                        |> Menu.viewBodyWithMaxRows 7
                        |> Tui.Screen.lines
                        |> Tui.Screen.toString
                        |> expectContains "Item 09"
            , test "keeps the rendered row count stable when scrolled near the end" <|
                \() ->
                    longMenu
                        |> navigateDownN 11
                        |> Menu.viewBodyWithMaxRows 7
                        |> List.length
                        |> Expect.equal 7
            ]
        , describe "duplicate items"
            [ test "navigating highlights the second identical item instead of the first" <|
                \() ->
                    let
                        rows =
                            duplicateMenu
                                |> navigateDownN 1
                                |> Menu.viewBody

                        firstDuplicateBg =
                            rows
                                |> List.drop 1
                                |> List.head
                                |> Maybe.map Tui.Screen.extractStyle
                                |> Maybe.andThen .bg

                        secondDuplicateBg =
                            rows
                                |> List.drop 2
                                |> List.head
                                |> Maybe.map Tui.Screen.extractStyle
                                |> Maybe.andThen .bg
                    in
                    Expect.all
                        [ \_ -> Expect.equal Nothing firstDuplicateBg
                        , \_ -> Expect.equal (Just Ansi.Color.blue) secondDuplicateBg
                        ]
                        ()
            ]
        , describe "Tui.Modal.maxBodyRows"
            [ test "matches the overlay clamp formula for a short terminal" <|
                \() ->
                    Expect.equal 7 (Modal.maxBodyRows 12)
            , test "matches the overlay clamp formula for a tall terminal" <|
                \() ->
                    Expect.equal 28 (Modal.maxBodyRows 40)
            ]
        ]


longMenu : Menu.State String
longMenu =
    Menu.open
        [ Menu.section "Actions"
            (List.range 1 12
                |> List.map
                    (\i ->
                        let
                            label =
                                "Item " ++ String.padLeft 2 '0' (String.fromInt i)

                            keyChar =
                                Char.fromCode (Char.toCode 'a' + i - 1)
                        in
                        Menu.item
                            { key = Tui.Sub.Character keyChar
                            , label = label
                            , action = label
                            }
                    )
            )
        ]


duplicateMenu : Menu.State String
duplicateMenu =
    Menu.open
        [ Menu.section "Duplicates"
            [ Menu.item
                { key = Tui.Sub.Character 'a'
                , label = "Same"
                , action = "same"
                }
            , Menu.item
                { key = Tui.Sub.Character 'a'
                , label = "Same"
                , action = "same"
                }
            ]
        ]


navigateDownN : Int -> Menu.State msg -> Menu.State msg
navigateDownN count state =
    if count <= 0 then
        state

    else
        let
            ( nextState, _ ) =
                Menu.handleKeyEvent
                    { key = Tui.Sub.Character 'j', modifiers = [] }
                    state
        in
        navigateDownN (count - 1) nextState


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
