module ModalTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Modal as Modal


suite : Test
suite =
    describe "Tui.Modal"
        [ describe "height clamping"
            [ test "modal with body shorter than terminal renders normally" <|
                \() ->
                    let
                        bgRows =
                            List.repeat 10 (Tui.text (String.repeat 40 " "))

                        result =
                            Modal.overlay
                                { title = "Small"
                                , body = [ Tui.text "line 1", Tui.text "line 2" ]
                                , footer = "ok"
                                , width = 30
                                }
                                { width = 40, height = 10 }
                                bgRows

                        rendered =
                            result |> List.map Tui.toString |> String.join "\n"
                    in
                    Expect.all
                        [ \s -> s |> String.contains "Small" |> Expect.equal True
                        , \s -> s |> String.contains "line 1" |> Expect.equal True
                        , \s -> s |> String.contains "line 2" |> Expect.equal True
                        , \s -> s |> String.contains "ok" |> Expect.equal True
                        -- Should have exactly 10 rows (same as terminal height)
                        , \_ -> List.length result |> Expect.equal 10
                        ]
                        rendered
            , test "modal taller than terminal is clamped with padding" <|
                \() ->
                    let
                        -- 20 body lines + 2 borders = 22, terminal is 10
                        -- Max body = 10 - 4 (2 borders + 2 padding) = 6
                        bodyLines =
                            List.range 1 20
                                |> List.map (\i -> Tui.text ("item " ++ String.fromInt i))

                        bgRows =
                            List.repeat 10 (Tui.text (String.repeat 40 " "))

                        result =
                            Modal.overlay
                                { title = "Big"
                                , body = bodyLines
                                , footer = "footer"
                                , width = 30
                                }
                                { width = 40, height = 10 }
                                bgRows

                        rendered =
                            result |> List.map Tui.toString |> String.join "\n"
                    in
                    Expect.all
                        [ -- Must not exceed terminal height
                          \_ -> List.length result |> Expect.equal 10
                        , -- Title border visible
                          \s -> s |> String.contains "Big" |> Expect.equal True
                        , -- Footer border visible (not pushed off screen)
                          \s -> s |> String.contains "footer" |> Expect.equal True
                        , -- First body item visible
                          \s -> s |> String.contains "item 1" |> Expect.equal True
                        , -- item 7+ should be truncated (only 6 body rows fit)
                          \s -> s |> String.contains "item 7" |> Expect.equal False
                        ]
                        rendered
            , test "clamped modal leaves padding rows at top and bottom" <|
                \() ->
                    let
                        -- 15 body lines, terminal height 10
                        -- Max body = 10 - 4 = 6, modal height = 8 (6 body + 2 borders)
                        -- startRow = (10 - 8) // 2 = 1 (1 row of bg visible above)
                        bodyLines =
                            List.range 1 15
                                |> List.map (\i -> Tui.text ("row " ++ String.fromInt i))

                        bgRows =
                            List.range 0 9
                                |> List.map (\i -> Tui.text ("bg" ++ String.fromInt i ++ String.repeat 37 " "))

                        result =
                            Modal.overlay
                                { title = "T"
                                , body = bodyLines
                                , footer = "f"
                                , width = 30
                                }
                                { width = 40, height = 10 }
                                bgRows

                        renderedRows =
                            result |> List.map Tui.toString
                    in
                    Expect.all
                        [ -- First row should be background (not modal)
                          \rows -> rows |> List.head |> Maybe.map (String.contains "bg0") |> Expect.equal (Just True)
                        , -- Last row should be background (not modal)
                          \rows -> rows |> List.reverse |> List.head |> Maybe.map (String.contains "bg9") |> Expect.equal (Just True)
                        , -- Body rows 1-6 visible
                          \rows -> rows |> String.join "\n" |> String.contains "row 1" |> Expect.equal True
                        , \rows -> rows |> String.join "\n" |> String.contains "row 6" |> Expect.equal True
                        , -- row 7 truncated
                          \rows -> rows |> String.join "\n" |> String.contains "row 7" |> Expect.equal False
                        ]
                        renderedRows
            , test "modal with fewer body rows than padding allows renders all rows" <|
                \() ->
                    let
                        -- 4 body lines + 2 borders = 6, terminal is 10
                        -- 6 < 10 so no clamping needed, all 4 body rows shown
                        bodyLines =
                            List.range 1 4
                                |> List.map (\i -> Tui.text ("line " ++ String.fromInt i))

                        bgRows =
                            List.repeat 10 (Tui.text (String.repeat 40 " "))

                        result =
                            Modal.overlay
                                { title = "Fits"
                                , body = bodyLines
                                , footer = "end"
                                , width = 30
                                }
                                { width = 40, height = 10 }
                                bgRows

                        rendered =
                            result |> List.map Tui.toString |> String.join "\n"
                    in
                    Expect.all
                        [ \s -> s |> String.contains "line 1" |> Expect.equal True
                        , \s -> s |> String.contains "line 4" |> Expect.equal True
                        , \s -> s |> String.contains "end" |> Expect.equal True
                        ]
                        rendered
            , test "modal with zero body lines still shows borders" <|
                \() ->
                    let
                        bgRows =
                            List.repeat 10 (Tui.text (String.repeat 40 " "))

                        result =
                            Modal.overlay
                                { title = "Empty"
                                , body = []
                                , footer = "ok"
                                , width = 30
                                }
                                { width = 40, height = 10 }
                                bgRows

                        rendered =
                            result |> List.map Tui.toString |> String.join "\n"
                    in
                    Expect.all
                        [ \s -> s |> String.contains "Empty" |> Expect.equal True
                        , \s -> s |> String.contains "ok" |> Expect.equal True
                        ]
                        rendered
            ]
        ]
