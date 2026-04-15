module BorderTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Layout as Layout
import Tui.Screen


suite : Test
suite =
    describe "Bottom border rendering"
        [ test "single pane has bottom border" <|
            \() ->
                Layout.horizontal
                    [ Layout.pane "box"
                        { title = "Box", width = Layout.fill }
                        (Layout.content [ Tui.Screen.text "content" ])
                    ]
                    |> renderLastRow { width = 20, height = 5 }
                    |> (\lastRow ->
                            Expect.all
                                [ \_ -> lastRow |> String.contains "╰" |> Expect.equal True |> Expect.onFail ("expected ╰ in: " ++ lastRow)
                                , \_ -> lastRow |> String.contains "╯" |> Expect.equal True |> Expect.onFail ("expected ╯ in: " ++ lastRow)
                                ]
                                ()
                       )
        , test "two panes both have bottom border" <|
            \() ->
                Layout.horizontal
                    [ Layout.pane "left"
                        { title = "Left", width = Layout.fill }
                        (Layout.content [ Tui.Screen.text "left" ])
                    , Layout.pane "right"
                        { title = "Right", width = Layout.fill }
                        (Layout.content [ Tui.Screen.text "right" ])
                    ]
                    |> renderLastRow { width = 40, height = 5 }
                    |> (\lastRow ->
                            Expect.all
                                [ \_ -> lastRow |> String.contains "╯ ╰" |> Expect.equal True |> Expect.onFail ("expected ╯ ╰ (gap between panes) in: " ++ lastRow)
                                ]
                                ()
                       )
        , test "bottom border present with withInlineFooter" <|
            \() ->
                Layout.horizontal
                    [ Layout.pane "left"
                        { title = "Modules", width = Layout.fill }
                        (Layout.selectableList
                            { onSelect = identity
                            , view =
                                \{ selection } item ->
                                    case selection of
                                        Layout.Selected _ ->
                                            Tui.Screen.text ("▸ " ++ item)

                                        Layout.NotSelected ->
                                            Tui.Screen.text ("  " ++ item)
                            }
                            (List.range 1 50 |> List.map (\i -> "Item " ++ String.fromInt i))
                        )
                        |> Layout.withInlineFooter (Tui.Screen.text "1 of 50")
                    , Layout.pane "right"
                        { title = "Detail", width = Layout.fill }
                        (Layout.content [ Tui.Screen.text "detail" ])
                        |> Layout.withInlineFooter (Tui.Screen.text "1 of 2")
                    ]
                    |> renderLastRow { width = 60, height = 20 }
                    |> (\lastRow ->
                            Expect.all
                                [ \_ -> lastRow |> String.contains "╰" |> Expect.equal True |> Expect.onFail ("expected ╰ in last row but was: " ++ lastRow)
                                , \_ -> lastRow |> String.contains "╯" |> Expect.equal True |> Expect.onFail ("expected ╯ in last row but was: " ++ lastRow)
                                ]
                                ()
                       )
        , test "bottom border present with withFooter" <|
            \() ->
                Layout.horizontal
                    [ Layout.pane "left"
                        { title = "Modules", width = Layout.fill }
                        (Layout.selectableList
                            { onSelect = identity
                            , view =
                                \{ selection } item ->
                                    case selection of
                                        Layout.Selected _ ->
                                            Tui.Screen.text ("▸ " ++ item)

                                        Layout.NotSelected ->
                                            Tui.Screen.text ("  " ++ item)
                            }
                            (List.range 1 50 |> List.map (\i -> "Item " ++ String.fromInt i))
                        )
                        |> Layout.withFooter "1 of 50"
                    , Layout.pane "right"
                        { title = "Detail", width = Layout.fill }
                        (Layout.content [ Tui.Screen.text "detail" ])
                        |> Layout.withFooter "1 of 2"
                    ]
                    |> renderLastRow { width = 60, height = 20 }
                    |> (\lastRow ->
                            Expect.all
                                [ \_ -> lastRow |> String.contains "╰" |> Expect.equal True |> Expect.onFail ("expected ╰ in last row but was: " ++ lastRow)
                                , \_ -> lastRow |> String.contains "╯" |> Expect.equal True |> Expect.onFail ("expected ╯ in last row but was: " ++ lastRow)
                                , \_ -> lastRow |> String.contains "1 of 50" |> Expect.equal True |> Expect.onFail ("expected footer text in last row but was: " ++ lastRow)
                                ]
                                ()
                       )
        , test "three panes with inline footers — last row is bottom border not content" <|
            \() ->
                let
                    items n =
                        List.range 1 n |> List.map (\i -> "Item " ++ String.fromInt i)
                in
                Layout.horizontal
                    [ Layout.pane "modules"
                        { title = "Modules", width = Layout.fill }
                        (Layout.selectableList
                            { onSelect = identity
                            , view = \_ item -> Tui.Screen.text item
                            }
                            (items 51)
                        )
                        |> Layout.withInlineFooter (Tui.Screen.text "1 of 51")
                    , Layout.pane "items"
                        { title = "Items", width = Layout.fill }
                        (Layout.selectableList
                            { onSelect = identity
                            , view = \_ item -> Tui.Screen.text item
                            }
                            (items 2)
                        )
                        |> Layout.withInlineFooter (Tui.Screen.text "1 of 2")
                    , Layout.pane "detail"
                        { title = "README", width = Layout.fill }
                        (Layout.content
                            (List.range 1 100 |> List.map (\i -> Tui.Screen.text ("Line " ++ String.fromInt i)))
                        )
                    ]
                    |> renderLastRow { width = 90, height = 25 }
                    |> (\lastRow ->
                            Expect.all
                                [ \_ -> lastRow |> String.contains "╰" |> Expect.equal True |> Expect.onFail ("expected ╰ in last row but was: " ++ lastRow)
                                , \_ -> lastRow |> String.contains "╯" |> Expect.equal True |> Expect.onFail ("expected ╯ in last row but was: " ++ lastRow)
                                , \_ -> lastRow |> String.contains "│" |> Expect.equal False |> Expect.onFail ("last row should NOT contain │ (side border) — it should be the bottom border, but was: " ++ lastRow)
                                ]
                                ()
                       )
        , test "inline footer row has correct width (gap between panes)" <|
            \() ->
                let
                    layout =
                        Layout.horizontal
                            [ Layout.pane "left"
                                { title = "Left", width = Layout.fill }
                                (Layout.content [ Tui.Screen.text "content" ])
                                |> Layout.withInlineFooter (Tui.Screen.text "footer L")
                            , Layout.pane "right"
                                { title = "Right", width = Layout.fill }
                                (Layout.content [ Tui.Screen.text "content" ])
                                |> Layout.withInlineFooter (Tui.Screen.text "footer R")
                            ]

                    rows =
                        layout
                            |> Layout.toRows (Layout.withContext { width = 40, height = 6 } Layout.init)
                            |> List.map Tui.Screen.toString

                    -- Row 0: top border, Row 1-3: content, Row 4: inline footer, Row 5: bottom border
                    -- All rows should have the same total width
                    topRow =
                        rows |> List.head |> Maybe.withDefault ""

                    inlineFooterRow =
                        rows |> List.drop 4 |> List.head |> Maybe.withDefault ""

                    bottomRow =
                        rows |> List.reverse |> List.head |> Maybe.withDefault ""
                in
                Expect.all
                    [ \_ ->
                        String.length inlineFooterRow
                            |> Expect.equal (String.length topRow)
                            |> Expect.onFail
                                ("inline footer row width ("
                                    ++ String.fromInt (String.length inlineFooterRow)
                                    ++ ") should match top border width ("
                                    ++ String.fromInt (String.length topRow)
                                    ++ ")\n  top row:    '"
                                    ++ topRow
                                    ++ "'\n  footer row: '"
                                    ++ inlineFooterRow
                                    ++ "'\n  bottom row: '"
                                    ++ bottomRow
                                    ++ "'"
                                )
                    , \_ ->
                        String.length bottomRow
                            |> Expect.equal (String.length topRow)
                            |> Expect.onFail
                                ("bottom border width ("
                                    ++ String.fromInt (String.length bottomRow)
                                    ++ ") should match top border width ("
                                    ++ String.fromInt (String.length topRow)
                                    ++ ")\n  top row:    '"
                                    ++ topRow
                                    ++ "'\n  bottom row: '"
                                    ++ bottomRow
                                    ++ "'"
                                )
                    ]
                    ()
        ]


renderLastRow : { width : Int, height : Int } -> Layout.Layout msg -> String
renderLastRow size layout =
    layout
        |> Layout.toRows (Layout.withContext size Layout.init)
        |> List.reverse
        |> List.head
        |> Maybe.map Tui.Screen.toString
        |> Maybe.withDefault ""
