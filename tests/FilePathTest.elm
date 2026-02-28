module FilePathTest exposing (all)

import Expect
import FilePath
import Test exposing (Test, describe, test)


all : Test
all =
    describe "FilePath"
        [ joinTests
        , relativeTests
        , absoluteTests
        , normalizationTests
        , filenameTests
        ]


joinTests : Test
joinTests =
    describe "join"
        [ test "joins paths left to right" <|
            \() ->
                FilePath.join
                    [ FilePath.fromString "a"
                    , FilePath.fromString "b"
                    , FilePath.fromString "c"
                    ]
                    |> FilePath.toString
                    |> Expect.equal "a/b/c"
        , test "join with absolute path resets" <|
            \() ->
                FilePath.join
                    [ FilePath.fromString "a"
                    , FilePath.fromString "/b"
                    , FilePath.fromString "c"
                    ]
                    |> FilePath.toString
                    |> Expect.equal "/b/c"
        , test "join three relative segments" <|
            \() ->
                FilePath.join
                    [ FilePath.fromString "foo"
                    , FilePath.fromString "bar"
                    , FilePath.fromString "baz"
                    ]
                    |> FilePath.toString
                    |> Expect.equal "foo/bar/baz"
        ]


relativeTests : Test
relativeTests =
    describe "relative"
        [ test "builds relative path from segments" <|
            \() ->
                FilePath.relative [ "usr", "bin" ]
                    |> FilePath.toString
                    |> Expect.equal "usr/bin"
        , test "empty segments produce dot" <|
            \() ->
                FilePath.relative []
                    |> FilePath.toString
                    |> Expect.equal "."
        ]


absoluteTests : Test
absoluteTests =
    describe "absolute"
        [ test "builds absolute path from segments" <|
            \() ->
                FilePath.absolute [ "usr", "bin" ]
                    |> FilePath.toString
                    |> Expect.equal "/usr/bin"
        , test "empty segments produce root" <|
            \() ->
                FilePath.absolute []
                    |> FilePath.toString
                    |> Expect.equal "/"
        ]


normalizationTests : Test
normalizationTests =
    describe "normalization"
        [ test "resolves .. in /foo/bar/baz/../../qux" <|
            \() ->
                FilePath.fromString "/foo/bar/baz/../../qux"
                    |> FilePath.toString
                    |> Expect.equal "/foo/qux"
        ]


filenameTests : Test
filenameTests =
    describe "filename helpers"
        [ test "filenameWithoutExtension returns name without extension" <|
            \() ->
                FilePath.fromString "src/Main.elm"
                    |> FilePath.filenameWithoutExtension
                    |> Expect.equal (Just "Main")
        ]
