module GlobTests exposing (all)

import Expect
import Glob
import Test exposing (Test, describe, test)


all : Test
all =
    describe "glob"
        [ test "literal" <|
            \() ->
                Glob.literal "hello"
                    |> expect "hello"
                        { expectedMatch = "hello"
                        , expectedPattern = "hello"
                        }
        , test "capture" <|
            \() ->
                Glob.succeed identity
                    |> Glob.capture Glob.wildcard
                    |> Glob.ignore (Glob.literal ".txt")
                    |> expect "my-file.txt"
                        { expectedMatch = "my-file"
                        , expectedPattern = "*.txt"
                        }
        , test "oneOf" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.capture Glob.wildcard
                    |> Glob.ignore (Glob.literal ".")
                    |> Glob.capture
                        (Glob.oneOf
                            ( ( "yml", Yml )
                            , [ ( "json", Json )
                              ]
                            )
                        )
                    -- https://runkit.com/embed/05epbnc0c7g1
                    |> expect "data-file.json"
                        { expectedMatch = ( "data-file", Json )
                        , expectedPattern = "*.(yml|json)"
                        }
        , test "at least one" <|
            \() ->
                Glob.succeed identity
                    |> Glob.ignore Glob.wildcard
                    |> Glob.ignore (Glob.literal ".")
                    |> Glob.capture
                        (Glob.atLeastOne
                            ( ( "yml", Yml )
                            , [ ( "json", Json )
                              ]
                            )
                        )
                    -- https://runkit.com/embed/05epbnc0c7g1
                    |> expect "data-file.jsonymljsonjson"
                        { expectedMatch = ( Json, [ Yml, Json, Json ] )
                        , expectedPattern = "*.+(yml|json)"
                        }
        , test "optional group - no match" <|
            \() ->
                zeroOrMoreGlob
                    |> expect "test/a/x.js"
                        -- test/a/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L42
                        { expectedMatch = Nothing
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "optional group - single match" <|
            \() ->
                zeroOrMoreGlob
                    |> expect "test/ab/x.js"
                        -- test/ab/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L44
                        { expectedMatch = Just "b"
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "optional group - multiple matches" <|
            \() ->
                zeroOrMoreGlob
                    |> expect "test/aba/x.js"
                        -- test/aba/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L45
                        { expectedMatch = Just "ba"
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "new star" <|
            \() ->
                Glob.wildcard
                    |> expect "star-pattern"
                        { expectedMatch = "star-pattern"
                        , expectedPattern = "*"
                        }
        , test "new star with literal" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.capture Glob.wildcard
                    |> Glob.ignore (Glob.literal "/")
                    |> Glob.capture (Glob.wildcard |> Glob.map String.toUpper)
                    |> Glob.ignore (Glob.literal ".txt")
                    |> expect "before-slash/after-slash.txt"
                        { expectedMatch = ( "before-slash", "AFTER-SLASH" )
                        , expectedPattern = "*/*.txt"
                        }
        , test "recursive match" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.capture Glob.recursiveWildcard
                    |> Glob.ignore (Glob.literal "/")
                    |> Glob.capture Glob.wildcard
                    |> Glob.ignore (Glob.literal ".txt")
                    |> expect "a/b/c/d.txt"
                        { expectedMatch = ( "a/b/c", "d" )
                        , expectedPattern = "**/*.txt"
                        }
        ]


zeroOrMoreGlob : Glob.Glob (Maybe String)
zeroOrMoreGlob =
    Glob.succeed identity
        |> Glob.ignore (Glob.literal "test/a")
        |> Glob.capture (Glob.zeroOrMore [ "a", "b" ])
        |> Glob.ignore (Glob.literal "/x.js")


type DataExtension
    = Yml
    | Json


expect :
    String
    ->
        { expectedMatch : match
        , expectedPattern : String
        }
    -> Glob.Glob match
    -> Expect.Expectation
expect filePath { expectedMatch, expectedPattern } glob =
    glob
        |> Glob.run filePath
        |> Expect.equal
            { pattern = expectedPattern
            , match = expectedMatch
            }
