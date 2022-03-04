module GlobTests exposing (all)

import DataSource.Glob as Glob
import DataSource.Internal.Glob
import Expect
import Test exposing (Test, describe, test)


all : Test
all =
    describe "glob"
        [ test "capture" <|
            \() ->
                Glob.succeed identity
                    |> Glob.capture Glob.wildcard
                    |> Glob.match (Glob.literal ".txt")
                    |> expect "my-file.txt"
                        { expectedMatch = "my-file"
                        , expectedPattern = "*.txt"
                        }
        , test "oneOf" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.capture Glob.wildcard
                    |> Glob.match (Glob.literal ".")
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
                        , expectedPattern = "*.{yml,json}"
                        }
        , test "mix of match and capture with wildcards" <|
            \() ->
                Glob.succeed identity
                    |> Glob.match Glob.wildcard
                    |> Glob.match (Glob.literal "/")
                    |> Glob.capture Glob.wildcard
                    |> expectAll
                        [ ( "match/capture", "capture" )
                        ]
        , test "mix of match and capture with wildcards 2" <|
            \() ->
                Glob.succeed identity
                    |> Glob.capture Glob.wildcard
                    |> Glob.match (Glob.literal "/")
                    |> Glob.match Glob.wildcard
                    |> expectAll
                        [ ( "capture/match", "capture" )
                        ]
        , test "oneOf with empty" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.capture Glob.wildcard
                    |> Glob.capture
                        (Glob.oneOf
                            ( ( "/index", WithIndex )
                            , [ ( "", NoIndex )
                              ]
                            )
                        )
                    |> expectAll
                        [ ( "hello/index", ( "hello", WithIndex ) )
                        , ( "hello", ( "hello", NoIndex ) )
                        ]
        , test "at least one" <|
            \() ->
                Glob.succeed identity
                    |> Glob.match Glob.wildcard
                    |> Glob.match (Glob.literal ".")
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
        , test "withFilePath" <|
            \() ->
                Glob.succeed identity
                    |> Glob.captureFilePath
                    |> Glob.match Glob.wildcard
                    |> Glob.match (Glob.literal ".txt")
                    |> expectAll
                        [ ( "hello.txt", "hello.txt" )
                        ]
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
        , test "recursive match" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.capture Glob.recursiveWildcard
                    |> Glob.match (Glob.literal "/")
                    |> Glob.capture Glob.wildcard
                    |> Glob.match (Glob.literal ".txt")
                    |> expect "a/b/c/d.txt"
                        { expectedMatch = ( [ "a", "b", "c" ], "d" )
                        , expectedPattern = "**/*.txt"
                        }
        , test "wildcard and recursiveWildcard in one pattern" <|
            \() ->
                Glob.succeed Tuple.pair
                    |> Glob.match (Glob.literal "content/")
                    |> Glob.capture Glob.recursiveWildcard
                    |> Glob.match (Glob.literal "/")
                    |> Glob.capture Glob.wildcard
                    |> Glob.match (Glob.literal ".md")
                    |> expectAll
                        [ ( "content/about.md", ( [], "about" ) )
                        , ( "content/community/meetups.md", ( [ "community" ], "meetups" ) )
                        ]
        , test "multiple wildcards" <|
            \() ->
                Glob.succeed
                    (\year month day slug ->
                        { year = year
                        , month = month
                        , day = day
                        , slug = slug
                        }
                    )
                    |> Glob.match (Glob.literal "archive/")
                    |> Glob.capture Glob.int
                    |> Glob.match (Glob.literal "/")
                    |> Glob.capture Glob.int
                    |> Glob.match (Glob.literal "/")
                    |> Glob.capture Glob.int
                    |> Glob.match (Glob.literal "/")
                    |> Glob.capture Glob.wildcard
                    |> Glob.match (Glob.literal ".md")
                    |> expectAll
                        [ ( "archive/1977/06/10/apple-2-released.md"
                          , { year = 1977
                            , month = 6
                            , day = 10
                            , slug = "apple-2-released"
                            }
                          )
                        ]
        ]


type HasIndex
    = WithIndex
    | NoIndex


zeroOrMoreGlob : Glob.Glob (Maybe String)
zeroOrMoreGlob =
    Glob.succeed identity
        |> Glob.match (Glob.literal "test/a")
        |> Glob.capture (Glob.zeroOrMore [ "a", "b" ])
        |> Glob.match (Glob.literal "/x.js")


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
        |> DataSource.Internal.Glob.run filePath
        |> Expect.equal
            { pattern = expectedPattern
            , match = expectedMatch
            }


expectAll :
    List ( String, match )
    -> Glob.Glob match
    -> Expect.Expectation
expectAll expectedPairs glob =
    expectedPairs
        |> List.map
            (\( filePath, _ ) ->
                ( filePath
                , glob
                    |> DataSource.Internal.Glob.run filePath
                    |> .match
                )
            )
        |> Expect.equalLists expectedPairs
