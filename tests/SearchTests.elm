module SearchTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui.Screen
import Tui.Search as Search


sampleContent : List Tui.Screen.Screen
sampleContent =
    [ Tui.Screen.text "First line of content"
    , Tui.Screen.text "Second line has a keyword here"
    , Tui.Screen.text "Third line is plain"
    , Tui.Screen.text "Fourth line has keyword again"
    , Tui.Screen.text "Fifth line"
    , Tui.Screen.text "Sixth keyword line"
    , Tui.Screen.text "Seventh line"
    , Tui.Screen.text "Eighth line"
    , Tui.Screen.text "Ninth line"
    , Tui.Screen.text "Tenth line at the end"
    ]


suite : Test
suite =
    describe "Tui.Search"
        [ describe "start"
            [ test "initial state has empty query" <|
                \() ->
                    Search.start
                        |> Search.query
                        |> Expect.equal ""
            , test "initial state has no matches" <|
                \() ->
                    Search.start
                        |> Search.matchCount sampleContent
                        |> Expect.equal 0
            ]
        , describe "typing"
            [ test "typing updates query" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.query
                        |> Expect.equal "keyword"
            , test "typing finds matches" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.matchCount sampleContent
                        |> Expect.equal 3
            , test "backspace removes last char" <|
                \() ->
                    Search.start
                        |> typeString "hello"
                        |> Search.backspace
                        |> Search.query
                        |> Expect.equal "hell"
            , test "case insensitive search" <|
                \() ->
                    Search.start
                        |> typeString "KEYWORD"
                        |> Search.matchCount sampleContent
                        |> Expect.equal 3
            , test "smart case: uppercase triggers case-sensitive" <|
                \() ->
                    Search.start
                        |> typeString "First"
                        |> Search.matchCount sampleContent
                        |> Expect.equal 1
            , test "no matches returns 0" <|
                \() ->
                    Search.start
                        |> typeString "nonexistent"
                        |> Search.matchCount sampleContent
                        |> Expect.equal 0
            ]
        , describe "match navigation"
            [ test "currentMatch starts at 0" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.currentMatch
                        |> Expect.equal 0
            , test "nextMatch advances" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.nextMatch sampleContent
                        |> Search.currentMatch
                        |> Expect.equal 1
            , test "nextMatch wraps around" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.nextMatch sampleContent
                        |> Search.nextMatch sampleContent
                        |> Search.nextMatch sampleContent
                        |> Search.currentMatch
                        |> Expect.equal 0
            , test "prevMatch goes backward" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.nextMatch sampleContent
                        |> Search.nextMatch sampleContent
                        |> Search.prevMatch sampleContent
                        |> Search.currentMatch
                        |> Expect.equal 1
            , test "prevMatch wraps to end" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.prevMatch sampleContent
                        |> Search.currentMatch
                        |> Expect.equal 2
            ]
        , describe "matchLineIndex"
            [ test "returns line index of current match" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.matchLineIndex sampleContent
                        |> Expect.equal (Just 1)
            , test "nextMatch returns next line" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.nextMatch sampleContent
                        |> Search.matchLineIndex sampleContent
                        |> Expect.equal (Just 3)
            , test "returns Nothing when no matches" <|
                \() ->
                    Search.start
                        |> typeString "nonexistent"
                        |> Search.matchLineIndex sampleContent
                        |> Expect.equal Nothing
            ]
        , describe "statusText"
            [ test "shows match position" <|
                \() ->
                    Search.start
                        |> typeString "keyword"
                        |> Search.statusText sampleContent
                        |> String.contains "1/3"
                        |> Expect.equal True
            , test "shows no matches" <|
                \() ->
                    Search.start
                        |> typeString "nope"
                        |> Search.statusText sampleContent
                        |> String.contains "no matches"
                        |> Expect.equal True
            ]
        ]


typeString : String -> Search.State -> Search.State
typeString str state =
    String.foldl (\c s -> Search.typeChar c s) state str
