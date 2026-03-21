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
            , test "modal taller than terminal is clamped to terminal height" <|
                \() ->
                    let
                        -- 20 body lines + 2 borders = 22 rows, but terminal is only 10
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
                        , -- Last body items truncated (item 20 should NOT appear)
                          \s -> s |> String.contains "item 20" |> Expect.equal False
                        ]
                        rendered
            , test "clamped modal shows all available body rows" <|
                \() ->
                    let
                        -- 15 body lines, terminal height 8
                        -- Max body = 8 - 2 (borders) = 6 rows
                        bodyLines =
                            List.range 1 15
                                |> List.map (\i -> Tui.text ("row " ++ String.fromInt i))

                        bgRows =
                            List.repeat 8 (Tui.text (String.repeat 40 " "))

                        result =
                            Modal.overlay
                                { title = "T"
                                , body = bodyLines
                                , footer = "f"
                                , width = 30
                                }
                                { width = 40, height = 8 }
                                bgRows

                        rendered =
                            result |> List.map Tui.toString |> String.join "\n"
                    in
                    Expect.all
                        [ -- rows 1-6 should be visible (8 height - 2 borders = 6 body rows)
                          \s -> s |> String.contains "row 1" |> Expect.equal True
                        , \s -> s |> String.contains "row 6" |> Expect.equal True
                        , -- row 7 should be truncated
                          \s -> s |> String.contains "row 7" |> Expect.equal False
                        ]
                        rendered
            , test "modal exactly fitting terminal renders without clamping" <|
                \() ->
                    let
                        -- 8 body lines + 2 borders = 10 = terminal height (exact fit)
                        bodyLines =
                            List.range 1 8
                                |> List.map (\i -> Tui.text ("line " ++ String.fromInt i))

                        bgRows =
                            List.repeat 10 (Tui.text (String.repeat 40 " "))

                        result =
                            Modal.overlay
                                { title = "Exact"
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
                        , \s -> s |> String.contains "line 8" |> Expect.equal True
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
