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
                                , \_ -> Expect.equal (Just Ansi.Color.red) first.style.fg
                                , \_ -> Expect.equal [ Screen.Bold ] first.style.attributes
                                , \_ -> Expect.equal "elm-pages" third.text
                                , \_ -> Expect.equal (Just "https://elm-pages.com") third.style.hyperlink
                                ]
                                ()

                        _ ->
                            Expect.fail "Expected a single line with three public spans"
            , test "fromLine rebuilds a screen from public spans" <|
                \() ->
                    let
                        plainStyle : Screen.Style
                        plainStyle =
                            Screen.plain

                        greenBoldStyle : Screen.Style
                        greenBoldStyle =
                            { plainStyle | fg = Just Ansi.Color.green, attributes = [ Screen.Bold ] }
                    in
                    [ { text = "Status", style = greenBoldStyle }
                    , { text = ": ready", style = plainStyle }
                    ]
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
