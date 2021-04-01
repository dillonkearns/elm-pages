module GlobTests exposing (all)

import Expect
import Glob
import Test exposing (describe, only, test)


all =
    describe "glob"
        [ test "literal" <|
            \() ->
                Glob.literal "hello"
                    |> expect
                        { captures = []
                        , expectedMatch = "hello"
                        , expectedPattern = "hello"
                        }
        , test "capture" <|
            \() ->
                Glob.succeed identity
                    |> Glob.keep Glob.wildcard
                    |> Glob.drop (Glob.literal ".txt")
                    |> expect
                        { captures = [ "my-file" ]
                        , expectedMatch = "my-file"
                        , expectedPattern = "*.txt"
                        }
        , test "oneOf" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.keep Glob.wildcard
                    |> Glob.drop (Glob.literal ".")
                    |> Glob.keep
                        (Glob.oneOf
                            ( ( "yml", Yml )
                            , [ ( "json", Json )
                              ]
                            )
                        )
                    -- https://runkit.com/embed/05epbnc0c7g1
                    |> expect
                        { captures = [ "data-file", "json" ]
                        , expectedMatch = ( "data-file", Json )
                        , expectedPattern = "*.(yml|json)"
                        }
        , test "at least one" <|
            \() ->
                Glob.succeed identity
                    |> Glob.drop Glob.wildcard
                    |> Glob.drop (Glob.literal ".")
                    |> Glob.keep
                        (Glob.atLeastOne
                            ( ( "yml", Yml )
                            , [ ( "json", Json )
                              ]
                            )
                        )
                    -- https://runkit.com/embed/05epbnc0c7g1
                    |> expect
                        { captures = [ "data-file", "jsonymljsonjson" ]
                        , expectedMatch = ( Json, [ Yml, Json, Json ] )
                        , expectedPattern = "*.+(yml|json)"
                        }
        , test "optional group - no match" <|
            \() ->
                zeroOrMoreGlob
                    |> expect
                        -- test/a/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L42
                        { captures = [ "" ]
                        , expectedMatch = Nothing
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "optional group - single match" <|
            \() ->
                zeroOrMoreGlob
                    |> expect
                        -- test/ab/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L44
                        { captures = [ "b" ]
                        , expectedMatch = Just "b"
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "optional group - multiple matches" <|
            \() ->
                zeroOrMoreGlob
                    |> expect
                        -- test/aba/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L45
                        { captures = [ "ba" ]
                        , expectedMatch = Just "ba"
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "new star" <|
            \() ->
                Glob.wildcard
                    |> expect
                        { captures = [ "star-pattern" ]
                        , expectedMatch = "star-pattern"
                        , expectedPattern = "*"
                        }
        , test "new star with literal" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.keep Glob.wildcard
                    |> Glob.drop (Glob.literal "/")
                    |> Glob.keep (Glob.wildcard |> Glob.map String.toUpper)
                    |> Glob.drop (Glob.literal ".txt")
                    |> expect
                        { captures = [ "before-slash", "after-slash" ]
                        , expectedMatch = ( "before-slash", "AFTER-SLASH" )
                        , expectedPattern = "*/*.txt"
                        }
        , test "recursive match" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.keep Glob.recursiveWildcard
                    |> Glob.drop (Glob.literal "/")
                    |> Glob.keep Glob.wildcard
                    |> Glob.drop (Glob.literal ".txt")
                    |> expect
                        { captures = [ "a/b/c", "d" ]
                        , expectedMatch = ( "a/b/c", "d" )
                        , expectedPattern = "**/*.txt"
                        }
        , test "not" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.keep
                        (Glob.notOneOf
                            ( "xyz", [] )
                        )
                    |> Glob.drop (Glob.literal "/")
                    |> Glob.keep Glob.wildcard
                    |> Glob.drop (Glob.literal ".txt")
                    |> expect
                        -- abc/d.txt
                        -- https://runkit.com/embed/05epbnc0c7g1
                        { captures = [ "abc", "d" ]
                        , expectedMatch = ( "abc", "d" )
                        , expectedPattern = "!(xyz)/*.txt"
                        }
        , test "not with multiple patterns" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.keep
                        (Glob.notOneOf ( "abz", [ "xyz" ] ))
                    |> Glob.drop (Glob.literal "/")
                    |> Glob.keep Glob.wildcard
                    |> Glob.drop (Glob.literal ".txt")
                    |> expect
                        -- abc/d.txt
                        -- https://runkit.com/embed/05epbnc0c7g1
                        { captures = [ "abc", "d" ]
                        , expectedMatch = ( "abc", "d" )
                        , expectedPattern = "!(abz|xyz)/*.txt"
                        }
        ]


zeroOrMoreGlob : Glob.Glob (Maybe String)
zeroOrMoreGlob =
    Glob.succeed identity
        |> Glob.drop (Glob.literal "test/a")
        |> Glob.keep (Glob.zeroOrMore [ "a", "b" ])
        |> Glob.drop (Glob.literal "/x.js")


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
        |> Glob.run
            { fullPath = "full-path"
            , captures = captures
            }
        |> Expect.equal
            { pattern = expectedPattern
            , match = expectedMatch
            }
