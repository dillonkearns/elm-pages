module Example exposing (..)

import Expect exposing (Expectation)
import Test exposing (..)


suite : Test
suite =
    test "Directory.includes" <|
        \() ->
            456
                |> Expect.equal 456
