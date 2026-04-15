module TuiPublicApiTests exposing (suite)

import Ansi.Color
import BackendTask
import Expect
import Test exposing (Test, describe, test)
import Tui.Effect as Effect
import Tui.Screen as Screen


suite : Test
suite =
    describe "public TUI API"
        [ describe "Screen.Screen"
            [ test "toSpanLines preserves styled text in public spans" <|
                \() ->
                    let
                        spanLines : List (List Screen.Span)
                        spanLines =
                            Screen.concat
                                [ Screen.text "Hello" |> Screen.fg Ansi.Color.red |> Screen.bold
                                , Screen.text " "
                                , Screen.text "elm-pages" |> Screen.link { url = "https://elm-pages.com" }
                                ]
                                |> Screen.toSpanLines
                    in
                    case spanLines of
                        [ first :: _ :: third :: [] ] ->
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
            , test "fromSpans rebuilds a screen from public spans" <|
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
                        |> Screen.fromSpans
                        |> Screen.toString
                        |> Expect.equal "Status: ready"
            , test "truncateSpans keeps style information on the truncated span" <|
                \() ->
                    let
                        plainStyle : Screen.Style
                        plainStyle =
                            Screen.plain

                        linkStyle : Screen.Style
                        linkStyle =
                            { plainStyle | hyperlink = Just "https://elm-pages.com" }
                    in
                    [ { text = "elm-pages toolkit", style = linkStyle } ]
                        |> Screen.truncateSpans 10
                        |> Expect.equal
                            [ { text = "elm-pages…", style = linkStyle } ]
            , test "wrapSpans preserves style information across wrapped lines" <|
                \() ->
                    let
                        plainStyle : Screen.Style
                        plainStyle =
                            Screen.plain

                        cyanStyle : Screen.Style
                        cyanStyle =
                            { plainStyle | fg = Just Ansi.Color.cyan }
                    in
                    [ { text = "hello world", style = cyanStyle } ]
                        |> Screen.wrapSpans 6
                        |> Expect.equal
                            [ [ { text = "hello", style = cyanStyle } ]
                            , [ { text = "world", style = cyanStyle } ]
                            ]
            ]
        , describe "Tui.Effect.fold"
            [ test "fold can inspect batched public effects without constructors" <|
                \() ->
                    let
                        describeEffect : Effect.Effect String -> List String
                        describeEffect currentEffect =
                            Effect.fold
                                { none = [ "none" ]
                                , batch = List.concatMap describeEffect
                                , backendTask = \_ -> [ "backend-task" ]
                                , exit = \code -> [ "exit:" ++ String.fromInt code ]
                                }
                                currentEffect
                    in
                    Effect.batch
                        [ BackendTask.succeed "done"
                            |> Effect.perform identity
                        , Effect.exitWithCode 2
                        ]
                        |> describeEffect
                        |> Expect.equal
                            [ "backend-task"
                            , "exit:2"
                            ]
            ]
        , describe "Screen.Screen width helpers"
            [ test "truncateSpans with non-positive width returns no spans" <|
                \() ->
                    [ { text = "hello", style = Screen.plain } ]
                        |> Screen.truncateSpans 0
                        |> Expect.equal []
            , test "wrapSpans with non-positive width returns no lines" <|
                \() ->
                    [ { text = "hello", style = Screen.plain } ]
                        |> Screen.wrapSpans 0
                        |> Expect.equal []
            , test "truncateSpans respects grapheme boundaries" <|
                \() ->
                    [ { text = "🙂x", style = Screen.plain } ]
                        |> Screen.truncateSpans 2
                        |> Expect.equal [ { text = "🙂x", style = Screen.plain } ]
            , test "wrapSpans respects grapheme boundaries" <|
                \() ->
                    [ { text = "áb", style = Screen.plain } ]
                        |> Screen.wrapSpans 1
                        |> Expect.equal
                            [ [ { text = "á", style = Screen.plain } ]
                            , [ { text = "b", style = Screen.plain } ]
                            ]
            ]
        ]
