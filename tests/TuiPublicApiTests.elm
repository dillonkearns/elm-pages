module TuiPublicApiTests exposing (suite)

import Ansi.Color
import BackendTask
import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Effect as Effect
import Tui.Screen as Screen


suite : Test
suite =
    describe "public TUI API"
        [ describe "Tui.Screen"
            [ test "toSpanLines preserves styled text in public spans" <|
                \() ->
                    let
                        spanLines : List (List Screen.Span)
                        spanLines =
                            Tui.concat
                                [ Tui.text "Hello" |> Tui.fg Ansi.Color.red |> Tui.bold
                                , Tui.text " "
                                , Tui.text "elm-pages" |> Tui.link { url = "https://elm-pages.com" }
                                ]
                                |> Screen.toSpanLines
                    in
                    case spanLines of
                        [ first :: _ :: third :: [] ] ->
                            Expect.all
                                [ \_ -> Expect.equal "Hello" first.text
                                , \_ -> Expect.equal (Just Ansi.Color.red) first.style.fg
                                , \_ -> Expect.equal [ Tui.Bold ] first.style.attributes
                                , \_ -> Expect.equal "elm-pages" third.text
                                , \_ -> Expect.equal (Just "https://elm-pages.com") third.style.hyperlink
                                ]
                                ()

                        _ ->
                            Expect.fail "Expected a single line with three public spans"
            , test "fromSpans rebuilds a screen from public spans" <|
                \() ->
                    let
                        plainStyle : Tui.Style
                        plainStyle =
                            Tui.plain

                        greenBoldStyle : Tui.Style
                        greenBoldStyle =
                            { plainStyle | fg = Just Ansi.Color.green, attributes = [ Tui.Bold ] }
                    in
                    [ { text = "Status", style = greenBoldStyle }
                    , { text = ": ready", style = plainStyle }
                    ]
                        |> Screen.fromSpans
                        |> Tui.toString
                        |> Expect.equal "Status: ready"
            , test "truncateSpans keeps style information on the truncated span" <|
                \() ->
                    let
                        plainStyle : Tui.Style
                        plainStyle =
                            Tui.plain

                        linkStyle : Tui.Style
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
                        plainStyle : Tui.Style
                        plainStyle =
                            Tui.plain

                        cyanStyle : Tui.Style
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
                                , toast = \message -> [ "toast:" ++ message ]
                                , errorToast = \message -> [ "error:" ++ message ]
                                , resetScroll = \paneId -> [ "reset:" ++ paneId ]
                                , scrollTo = \paneId offset -> [ "scrollTo:" ++ paneId ++ ":" ++ String.fromInt offset ]
                                , scrollDown = \paneId amount -> [ "scrollDown:" ++ paneId ++ ":" ++ String.fromInt amount ]
                                , scrollUp = \paneId amount -> [ "scrollUp:" ++ paneId ++ ":" ++ String.fromInt amount ]
                                , setSelectedIndex = \paneId index -> [ "setSelectedIndex:" ++ paneId ++ ":" ++ String.fromInt index ]
                                , selectFirst = \paneId -> [ "selectFirst:" ++ paneId ]
                                , focusPane = \paneId -> [ "focus:" ++ paneId ]
                                }
                                currentEffect
                    in
                    Effect.batch
                        [ Effect.toast "Saved"
                        , Effect.scrollDown "files" 3
                        , BackendTask.succeed "done"
                            |> Effect.perform identity
                        , Effect.exitWithCode 2
                        ]
                        |> describeEffect
                        |> Expect.equal
                            [ "toast:Saved"
                            , "scrollDown:files:3"
                            , "backend-task"
                            , "exit:2"
                            ]
            ]
        ]
