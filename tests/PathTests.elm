module PathTests exposing (..)

import Expect exposing (Expectation)
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
            ]
