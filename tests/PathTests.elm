module PathTests exposing (all)

import Expect
import FatalError
import Path
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Path"
        [ test "join two segments" <|
            \() ->
                Path.join [ "a", "b", "c" ]
                    |> Path.toAbsolute
                    |> Expect.equal "/a/b/c"
        , test "join segments that have paths in them" <|
            \() ->
                Path.join [ "a", "b", "c/d/e" ]
                    |> Path.toAbsolute
                    |> Expect.equal "/a/b/c/d/e"
        , test "removes trailing and leading slashes" <|
            \() ->
                Path.join [ "a/", "/b/", "/c/d/e/" ]
                    |> Path.toAbsolute
                    |> Expect.equal "/a/b/c/d/e"
        , test "fromString with trailing and leading" <|
            \() ->
                Path.fromString "/blog/post-1/"
                    |> Path.toAbsolute
                    |> Expect.equal "/blog/post-1"
        , test "fromString without trailing and leading" <|
            \() ->
                Path.fromString "blog/post-1"
                    |> Path.toAbsolute
                    |> Expect.equal "/blog/post-1"
        ]
