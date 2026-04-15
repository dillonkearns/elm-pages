module ModalTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Modal as Modal
import Tui.Screen


suite : Test
suite =
    describe "Tui.Modal"
        [ describe "height clamping (lazygit: 75% of terminal height)"
            [ test "modal with body shorter than 75% renders normally" <|
                \() ->
                    let
                        bgRows : List Tui.Screen.Screen
                        bgRows =
                            List.repeat 20 (Tui.Screen.text (String.repeat 40 " "))

                        result : List Tui.Screen.Screen
                        result =
                            Modal.overlay
                                { title = "Small"
                                , body = [ Tui.Screen.text "line 1", Tui.Screen.text "line 2" ]
                                , footer = "ok"
                                , width = 30
                                }
                                { width = 40, height = 20 }
                                bgRows

                        rendered : String
                        rendered =
                            result |> List.map Tui.Screen.toString |> String.join "\n"
                    in
                    Expect.all
                        [ \s -> s |> String.contains "Small" |> Expect.equal True
                        , \s -> s |> String.contains "line 1" |> Expect.equal True
                        , \s -> s |> String.contains "line 2" |> Expect.equal True
                        , \s -> s |> String.contains "ok" |> Expect.equal True
                        , \_ -> List.length result |> Expect.equal 20
                        ]
                        rendered
            , test "modal taller than 75% is clamped" <|
                \() ->
                    let
                        -- 20 body lines, terminal height 20
                        -- Max modal = 20 * 3 // 4 = 15, max body = 15 - 2 = 13
                        bodyLines : List Tui.Screen.Screen
                        bodyLines =
                            List.range 1 20
                                |> List.map (\i -> Tui.Screen.text ("item " ++ String.fromInt i))

                        bgRows : List Tui.Screen.Screen
                        bgRows =
                            List.repeat 20 (Tui.Screen.text (String.repeat 40 " "))

                        result : List Tui.Screen.Screen
                        result =
                            Modal.overlay
                                { title = "Big"
                                , body = bodyLines
                                , footer = "footer"
                                , width = 30
                                }
                                { width = 40, height = 20 }
                                bgRows

                        rendered : String
                        rendered =
                            result |> List.map Tui.Screen.toString |> String.join "\n"
                    in
                    Expect.all
                        [ \_ -> List.length result |> Expect.equal 20
                        , \s -> s |> String.contains "Big" |> Expect.equal True
                        , \s -> s |> String.contains "footer" |> Expect.equal True
                        , \s -> s |> String.contains "item 1" |> Expect.equal True
                        , \s -> s |> String.contains "item 13" |> Expect.equal True
                        , -- item 14 should be truncated (max body = 13)
                          \s -> s |> String.contains "item 14" |> Expect.equal False
                        ]
                        rendered
            , test "clamped modal leaves background visible at top and bottom" <|
                \() ->
                    let
                        -- 50 body lines, terminal height 24
                        -- Max modal = 24 * 3 // 4 = 18, max body = 16
                        -- Modal height = 18 (16 body + 2 borders)
                        -- startRow = (24 - 18) // 2 = 3 (3 rows of bg above)
                        bodyLines : List Tui.Screen.Screen
                        bodyLines =
                            List.range 1 50
                                |> List.map (\i -> Tui.Screen.text ("row " ++ String.fromInt i))

                        bgRows : List Tui.Screen.Screen
                        bgRows =
                            List.range 0 23
                                |> List.map (\i -> Tui.Screen.text ("bg" ++ String.fromInt i ++ String.repeat 37 " "))

                        result : List Tui.Screen.Screen
                        result =
                            Modal.overlay
                                { title = "T"
                                , body = bodyLines
                                , footer = "f"
                                , width = 30
                                }
                                { width = 40, height = 24 }
                                bgRows

                        renderedRows : List String
                        renderedRows =
                            result |> List.map Tui.Screen.toString
                    in
                    Expect.all
                        [ -- First 3 rows should be background
                          \rows -> rows |> List.head |> Maybe.map (String.contains "bg0") |> Expect.equal (Just True)
                        , \rows -> rows |> List.drop 2 |> List.head |> Maybe.map (String.contains "bg2") |> Expect.equal (Just True)
                        , -- Last 3 rows should be background
                          \rows -> rows |> List.reverse |> List.head |> Maybe.map (String.contains "bg23") |> Expect.equal (Just True)
                        , -- Body rows visible
                          \rows -> rows |> String.join "\n" |> String.contains "row 1" |> Expect.equal True
                        , \rows -> rows |> String.join "\n" |> String.contains "row 16" |> Expect.equal True
                        , \rows -> rows |> String.join "\n" |> String.contains "row 17" |> Expect.equal False
                        ]
                        renderedRows
            , test "small terminal (height 8): modal uses 75% = 6 rows" <|
                \() ->
                    let
                        -- height 8, max modal = 8 * 3 // 4 = 6, max body = 4
                        bodyLines : List Tui.Screen.Screen
                        bodyLines =
                            List.range 1 20
                                |> List.map (\i -> Tui.Screen.text ("x" ++ String.fromInt i))

                        bgRows : List Tui.Screen.Screen
                        bgRows =
                            List.repeat 8 (Tui.Screen.text (String.repeat 40 " "))

                        result : List Tui.Screen.Screen
                        result =
                            Modal.overlay
                                { title = "S"
                                , body = bodyLines
                                , footer = "f"
                                , width = 30
                                }
                                { width = 40, height = 8 }
                                bgRows

                        rendered : String
                        rendered =
                            result |> List.map Tui.Screen.toString |> String.join "\n"
                    in
                    Expect.all
                        [ \s -> s |> String.contains "x1" |> Expect.equal True
                        , \s -> s |> String.contains "x4" |> Expect.equal True
                        , \s -> s |> String.contains "x5" |> Expect.equal False
                        , \s -> s |> String.contains "f" |> Expect.equal True
                        ]
                        rendered
            , test "modal with zero body lines still shows borders" <|
                \() ->
                    let
                        bgRows : List Tui.Screen.Screen
                        bgRows =
                            List.repeat 10 (Tui.Screen.text (String.repeat 40 " "))

                        result : List Tui.Screen.Screen
                        result =
                            Modal.overlay
                                { title = "Empty"
                                , body = []
                                , footer = "ok"
                                , width = 30
                                }
                                { width = 40, height = 10 }
                                bgRows

                        rendered : String
                        rendered =
                            result |> List.map Tui.Screen.toString |> String.join "\n"
                    in
                    Expect.all
                        [ \s -> s |> String.contains "Empty" |> Expect.equal True
                        , \s -> s |> String.contains "ok" |> Expect.equal True
                        ]
                        rendered
            ]
        ]
