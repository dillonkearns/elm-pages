module PathTests exposing (..)

import Expect exposing (Expectation)
import Path
import Test exposing (..)


all : Test
all =
    only <|
        describe "Path"
            [ test "there is no content flash during hydration" <|
                \() ->
                    Path.fromList [ "blog", "generate-files" ]
                        |> Path.toRelative
                        |> Expect.equal "blog/generate-files"
            ]
