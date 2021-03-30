module GlobTests exposing (all)

import Expect
import Glob
import Test exposing (describe, only, test)


all =
    describe "glob"
        [ test "literal" <|
            \() ->
                Glob.init identity
                    |> Glob.keep (Glob.literal "hello")
                    |> expect
                        { captures = []
                        , expectedMatch = "hello"
                        , expectedPattern = "hello"
                        }
        , test "capture" <|
            \() ->
                Glob.init identity
                    |> Glob.keep Glob.star
                    |> Glob.drop (Glob.literal ".txt")
                    |> expect
                        { captures = [ "my-file" ]
                        , expectedMatch = "my-file"
                        , expectedPattern = "*.txt"
                        }
        ]


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
