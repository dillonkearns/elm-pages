module PathTests exposing (all)

import Expect
import Test exposing (Test, describe, test)
import UrlPath


all : Test
all =
    describe "UrlPath"
        [ test "join two segments" <|
            \() ->
                UrlPath.join [ "a", "b", "c" ]
                    |> UrlPath.toAbsolute
                    |> Expect.equal "/a/b/c"
        , test "join segments that have paths in them" <|
            \() ->
                UrlPath.join [ "a", "b", "c/d/e" ]
                    |> UrlPath.toAbsolute
                    |> Expect.equal "/a/b/c/d/e"
        , test "removes trailing and leading slashes" <|
            \() ->
                UrlPath.join [ "a/", "/b/", "/c/d/e/" ]
                    |> UrlPath.toAbsolute
                    |> Expect.equal "/a/b/c/d/e"
        , test "fromString with trailing and leading" <|
            \() ->
                UrlPath.fromString "/blog/post-1/"
                    |> UrlPath.toAbsolute
                    |> Expect.equal "/blog/post-1"
        , test "fromString without trailing and leading" <|
            \() ->
                UrlPath.fromString "blog/post-1"
                    |> UrlPath.toAbsolute
                    |> Expect.equal "/blog/post-1"
        ]
