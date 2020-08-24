module PathTests exposing (..)

import Expect exposing (Expectation)
import Fuzz
import Path
import Test exposing (..)


all : Test
all =
    only <|
        describe "Path"
            [ test "convert from list" <|
                \() ->
                    Path.fromList [ "blog", "generate-files" ]
                        |> Path.toRelative
                        |> Expect.equal "blog/generate-files"
            , test "convert to list" <|
                \() ->
                    { path = "/blog/generate-files/" }
                        |> Path.fromPath
                        |> Path.toList
                        |> Expect.equal [ "blog", "generate-files" ]
            , fuzz pathListFuzzer "round trip" <|
                \list ->
                    list
                        |> Path.fromList
                        |> Path.toList
                        |> Expect.equal list
            ]


pathListFuzzer =
    Fuzz.list nonEmptyStringFuzzer


validCharacters =
    Fuzz.intRange 65 90
        |> Fuzz.map Char.fromCode


nonEmptyStringFuzzer =
    Fuzz.map2
        (\first rest ->
            (first :: rest) |> String.fromList
        )
        validCharacters
        (Fuzz.list validCharacters)
