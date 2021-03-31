module GlobTests exposing (all)

import Expect
import Glob
import Test exposing (describe, only, test)


all =
    only <|
        describe "glob"
            [ test "literal" <|
                \() ->
                    Glob.literal2 "hello"
                        |> expect2
                            { captures = []
                            , expectedMatch = "hello"
                            , expectedPattern = "hello"
                            }
            , test "capture" <|
                \() ->
                    Glob.succeed2 identity
                        |> Glob.keep2 Glob.star2
                        |> Glob.drop2 (Glob.literal2 ".txt")
                        |> expect2
                            { captures = [ "my-file" ]
                            , expectedMatch = "my-file"
                            , expectedPattern = "*.txt"
                            }
            , test "oneOf" <|
                \() ->
                    Glob.succeed2 Tuple.pair
                        |> Glob.keep2 Glob.star2
                        |> Glob.drop2 (Glob.literal2 ".")
                        |> Glob.keep2
                            (Glob.oneOf2
                                ( ( "yml", Yml )
                                , [ ( "json", Json )
                                  ]
                                )
                            )
                        |> expect2
                            { captures = [ "data-file", "json" ]
                            , expectedMatch = ( "data-file", Json )
                            , expectedPattern = "*.{yml,json}"
                            }
            , test "optional group - no match" <|
                \() ->
                    zeroOrMoreGlob
                        |> expect2
                            -- test/a/x.js
                            -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L42
                            { captures = [ "" ]
                            , expectedMatch = Nothing
                            , expectedPattern = "test/a*(a|b)/x.js"
                            }
            , test "optional group - single match" <|
                \() ->
                    zeroOrMoreGlob
                        |> expect2
                            -- test/ab/x.js
                            -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L44
                            { captures = [ "b" ]
                            , expectedMatch = Just "b"
                            , expectedPattern = "test/a*(a|b)/x.js"
                            }
            , test "optional group - multiple matches" <|
                \() ->
                    zeroOrMoreGlob
                        |> expect2
                            -- test/aba/x.js
                            -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L45
                            { captures = [ "ba" ]
                            , expectedMatch = Just "ba"
                            , expectedPattern = "test/a*(a|b)/x.js"
                            }
            , test "new star" <|
                \() ->
                    Glob.star2
                        |> expect2
                            { captures = [ "star-pattern" ]
                            , expectedMatch = "star-pattern"
                            , expectedPattern = "*"
                            }
            , test "new star with literal" <|
                \() ->
                    Glob.succeed2 Tuple.pair
                        |> Glob.keep2 Glob.star2
                        |> Glob.drop2 (Glob.literal2 "/")
                        |> Glob.keep2 (Glob.star2 |> Glob.map String.toUpper)
                        |> Glob.drop2 (Glob.literal2 ".txt")
                        |> expect2
                            { captures = [ "before-slash", "after-slash" ]
                            , expectedMatch = ( "before-slash", "AFTER-SLASH" )
                            , expectedPattern = "*/*.txt"
                            }
            ]


zeroOrMoreGlob : Glob.NewGlob (Maybe String)
zeroOrMoreGlob =
    Glob.succeed2 identity
        |> Glob.drop2 (Glob.literal2 "test/a")
        |> Glob.keep2 (Glob.zeroOrMore2 [ "a", "b" ])
        |> Glob.drop2 (Glob.literal2 "/x.js")


type DataExtension
    = Yml
    | Json


expect :
    { captures : List String
    , expectedMatch : match
    , expectedPattern : String
    }
    -> Glob.Glob match
    -> Expect.Expectation
expect { captures, expectedMatch, expectedPattern } glob =
    glob
        |> Glob.run captures
        |> Expect.equal
            { pattern = expectedPattern
            , match = expectedMatch
            }


expect2 :
    { captures : List String
    , expectedMatch : match
    , expectedPattern : String
    }
    -> Glob.NewGlob match
    -> Expect.Expectation
expect2 { captures, expectedMatch, expectedPattern } glob =
    glob
        |> Glob.runNew captures
        |> Expect.equal
            { pattern = expectedPattern
            , match = expectedMatch
            }
