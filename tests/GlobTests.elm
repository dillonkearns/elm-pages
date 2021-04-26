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
                        { captures = []
                        , expectedMatch = "hello"
                        , expectedPattern = "hello"
                        }
        , test "capture" <|
            \() ->
                Glob.succeed identity
                    |> Glob.capture Glob.wildcard
                    |> Glob.ignore (Glob.literal ".txt")
                    |> expect "my-file.txt"
                        { captures = [ "my-file" ]
                        , expectedMatch = "my-file"
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
                        { captures = [ "data-file", "json" ]
                        , expectedMatch = ( "data-file", Json )
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
                        { captures = [ "data-file", "jsonymljsonjson" ]
                        , expectedMatch = ( Json, [ Yml, Json, Json ] )
                        , expectedPattern = "*.+(yml|json)"
                        }
        , test "optional group - no match" <|
            \() ->
                zeroOrMoreGlob
                    |> expect "test/a/x.js"
                        -- test/a/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L42
                        { captures = [ "" ]
                        , expectedMatch = Nothing
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "optional group - single match" <|
            \() ->
                zeroOrMoreGlob
                    |> expect "test/ab/x.js"
                        -- test/ab/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L44
                        { captures = [ "b" ]
                        , expectedMatch = Just "b"
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "optional group - multiple matches" <|
            \() ->
                zeroOrMoreGlob
                    |> expect "test/aba/x.js"
                        -- test/aba/x.js
                        -- https://github.com/micromatch/micromatch/blob/fe4858b0c63b174fd3ae22674db39119b8fa4392/test/api.capture.js#L45
                        { captures = [ "ba" ]
                        , expectedMatch = Just "ba"
                        , expectedPattern = "test/a*(a|b)/x.js"
                        }
        , test "new star" <|
            \() ->
                Glob.wildcard
                    |> expect "star-pattern"
                        { captures = [ "star-pattern" ]
                        , expectedMatch = "star-pattern"
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
                        { captures = [ "before-slash", "after-slash" ]
                        , expectedMatch = ( "before-slash", "AFTER-SLASH" )
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
                        { captures = [ "a/b/c", "d" ]
                        , expectedMatch = ( "a/b/c", "d" )
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
        { captures : List String
        , expectedMatch : match
        , expectedPattern : String
        }
    -> Glob.Glob match
    -> Expect.Expectation
expect filePath { captures, expectedMatch, expectedPattern } glob =
    glob
        |> Glob.run filePath
            { fullPath = "full-path"
            , captures = captures
            }
        |> Expect.equal
            { pattern = expectedPattern
            , match = expectedMatch
            }
