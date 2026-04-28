module FuzzyMatchTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui.FuzzyMatch as FuzzyMatch


suite : Test
suite =
    describe "Tui.FuzzyMatch"
        [ describe "match"
            [ test "exact match" <|
                \() ->
                    FuzzyMatch.match "hello" "hello"
                        |> Expect.equal True
            , test "substring match" <|
                \() ->
                    FuzzyMatch.match "ello" "hello"
                        |> Expect.equal True
            , test "fuzzy match — characters in order" <|
                \() ->
                    FuzzyMatch.match "jde" "Json.Decode"
                        |> Expect.equal True
            , test "fuzzy match — case insensitive" <|
                \() ->
                    FuzzyMatch.match "JDE" "Json.Decode"
                        |> Expect.equal True
            , test "no match — wrong order" <|
                \() ->
                    FuzzyMatch.match "edj" "Json.Decode"
                        |> Expect.equal False
            , test "no match — missing characters" <|
                \() ->
                    FuzzyMatch.match "xyz" "Json.Decode"
                        |> Expect.equal False
            , test "empty query matches everything" <|
                \() ->
                    FuzzyMatch.match "" "anything"
                        |> Expect.equal True
            , test "query longer than candidate fails" <|
                \() ->
                    FuzzyMatch.match "toolong" "hi"
                        |> Expect.equal False
            ]
        , describe "score"
            [ test "exact match scores highest" <|
                \() ->
                    let
                        exactScore : Int
                        exactScore =
                            FuzzyMatch.score "Json" "Json"

                        fuzzyScore : Int
                        fuzzyScore =
                            FuzzyMatch.score "Jsn" "Json"
                    in
                    (exactScore > fuzzyScore) |> Expect.equal True
            , test "consecutive chars score higher" <|
                \() ->
                    let
                        consecutiveScore : Int
                        consecutiveScore =
                            FuzzyMatch.score "Dec" "Json.Decode"

                        scatteredScore : Int
                        scatteredScore =
                            FuzzyMatch.score "Jde" "Json.Decode"
                    in
                    (consecutiveScore > scatteredScore) |> Expect.equal True
            , test "start-of-word bonus" <|
                \() ->
                    let
                        startScore : Int
                        startScore =
                            FuzzyMatch.score "JD" "Json.Decode"

                        midScore : Int
                        midScore =
                            FuzzyMatch.score "so" "Json.Decode"
                    in
                    (startScore > midScore) |> Expect.equal True
            , test "non-match returns 0" <|
                \() ->
                    FuzzyMatch.score "xyz" "Json.Decode"
                        |> Expect.equal 0
            ]
        , describe "highlight"
            [ test "returns Nothing on no match" <|
                \() ->
                    FuzzyMatch.highlight "xyz" "Json.Decode"
                        |> Expect.equal Nothing
            , test "highlights matched characters" <|
                \() ->
                    FuzzyMatch.highlight "jde" "Json.Decode"
                        |> Maybe.map (List.map .matched)
                        |> Expect.notEqual Nothing
            , test "highlight segments have correct text" <|
                \() ->
                    let
                        result : Maybe (List { text : String, matched : Bool })
                        result =
                            FuzzyMatch.highlight "JD" "Json.Decode"

                        allText : String
                        allText =
                            result
                                |> Maybe.withDefault []
                                |> List.map .text
                                |> String.concat
                    in
                    -- All segments concatenated should equal the original string
                    allText |> Expect.equal "Json.Decode"
            , test "highlight marks matched chars" <|
                \() ->
                    let
                        matchedChars : String
                        matchedChars =
                            FuzzyMatch.highlight "JD" "Json.Decode"
                                |> Maybe.withDefault []
                                |> List.filter .matched
                                |> List.map .text
                                |> String.concat
                    in
                    matchedChars |> Expect.equal "JD"
            ]
        ]
