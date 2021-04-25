module GlobTestsNew exposing (all)

import Expect
import Parser exposing ((|.), (|=), Parser)
import Test exposing (Test, describe, test)


{-| -}
type Glob a
    = Glob
        { pattern : String
        , regexPattern : String
        , capture : Parser a
        }


{-| -}
literal : String -> Glob String
literal string =
    Glob
        { pattern = string
        , regexPattern = string
        , capture =
            Parser.succeed string
                |. Parser.symbol string
        }


{-| -}
succeed : match -> Glob match
succeed string =
    Glob
        { pattern = ""
        , regexPattern = ""
        , capture =
            Parser.succeed string
        }


wildcard : Glob String
wildcard =
    Glob
        { pattern = "*"
        , regexPattern = ".*"
        , capture =
            --Parser.
            Parser.getChompedString
                (Parser.chompUntilEndOr "/")

        --\filePath ->
        --    ( string, filePath )
        }


capture : Glob a -> Glob (a -> value) -> Glob value
capture (Glob next) (Glob previous) =
    Glob
        { pattern = previous.pattern ++ next.pattern
        , regexPattern = ""
        , capture =
            Parser.backtrackable
                (previous.capture
                    |= next.capture
                )
        }


ignore : Glob a -> Glob b -> Glob b
ignore (Glob next) (Glob previous) =
    Glob
        { pattern = previous.pattern ++ next.pattern
        , regexPattern = ""
        , capture =
            Parser.backtrackable
                (Parser.succeed identity
                    |= previous.capture
                    |. next.capture
                )
        }


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
        , test "capture 1" <|
            \() ->
                succeed identity
                    |> capture wildcard
                    |> ignore (literal "/hello.txt")
                    |> expect "folder/hello.txt"
                        { expectedMatch = "folder"
                        , expectedPattern = "*/hello.txt"
                        }
        , test "capture" <|
            \() ->
                succeed identity
                    |> capture wildcard
                    |> ignore (literal ".txt")
                    |> expect "my-file.txt"
                        { expectedMatch = "my-file"
                        , expectedPattern = "*.txt"
                        }
        ]


type DataExtension
    = Yml
    | Json


run : String -> Glob match -> match
run filePath (Glob details) =
    case Parser.run details.capture filePath of
        Err errors ->
            Debug.todo <| Debug.toString errors

        Ok ok ->
            ok


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
