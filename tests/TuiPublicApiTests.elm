module TuiPublicApiTests exposing (suite)

import Ansi.Color
import Expect
import Test exposing (Test, describe, test)
import Tui.Screen as Screen
import Tui.Screen.Advanced as Advanced


suite : Test
suite =
    describe "public TUI API"
        [ describe "Tui.Screen.Advanced"
            [ test "toLines preserves styled text in public spans" <|
                \() ->
                    let
                        lines : List Advanced.Line
                        lines =
                            Screen.concat
                                [ Screen.text "Hello" |> Screen.fg Ansi.Color.red |> Screen.bold
                                , Screen.text " "
                                , Screen.text "elm-pages" |> Screen.link { url = "https://elm-pages.com" }
                                ]
                                |> Advanced.toLines
                    in
                    case lines of
                        [ [ first, _, third ] ] ->
                            Expect.all
                                [ \_ -> Expect.equal "Hello" first.text
                                , \_ -> Expect.equal (Just Ansi.Color.red) (Advanced.styleForeground first.style)
                                , \_ -> Expect.equal [ Screen.Bold ] (Advanced.styleAttributes first.style)
                                , \_ -> Expect.equal "elm-pages" third.text
                                , \_ -> Expect.equal (Just "https://elm-pages.com") (Advanced.styleHyperlink third.style)
                                ]
                                ()

                        _ ->
                            Expect.fail "Expected a single line with three public spans"
            , test "fromLine rebuilds a screen from public spans" <|
                \() ->
                    let
                        source : Screen.Screen
                        source =
                            Screen.concat
                                [ Screen.text "Status" |> Screen.fg Ansi.Color.green |> Screen.bold
                                , Screen.text ": ready"
                                ]
                    in
                    source
                        |> Advanced.toLines
                        |> List.head
                        |> Maybe.withDefault []
                        |> Advanced.fromLine
                        |> Screen.toString
                        |> Expect.equal "Status: ready"
            , test "fromLine [] preserves a blank rendered line" <|
                \() ->
                    []
                        |> Advanced.fromLine
                        |> Advanced.toLines
                        |> Expect.equal [ [] ]
            ]
        ]
