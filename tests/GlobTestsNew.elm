module GlobTestsNew exposing (all)

import Expect
import Test exposing (Test, describe, test)


{-| -}
type Glob a
    = Glob { pattern : String, regexPattern : String, capture : String -> ( a, String ) }


{-| -}
literal : String -> Glob String
literal string =
    Glob { pattern = string, regexPattern = string, capture = \filePath -> ( string, filePath ) }


all : Test
all =
    describe "glob"
        [ test "literal" <|
            \() ->
                literal "hello"
                    |> expect "hello"
                        { expectedMatch = "hello"
                        , expectedPattern = "hello"
                        }
        ]


type DataExtension
    = Yml
    | Json


run : String -> Glob match -> match
run filePath (Glob { pattern, regexPattern, capture }) =
    capture filePath
        |> Tuple.first


expect :
    String
    ->
        { expectedMatch : match
        , expectedPattern : String
        }
    -> Glob match
    -> Expect.Expectation
expect filePath { expectedMatch, expectedPattern } glob =
    { pattern = getPattern glob
    , match = glob |> run filePath
    }
        |> Expect.equal
            { pattern = expectedPattern
            , match = expectedMatch
            }


getPattern : Glob match -> String
getPattern (Glob { pattern }) =
    pattern
