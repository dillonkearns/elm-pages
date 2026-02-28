module FilePathTest exposing (all)

import Expect
import FilePath
import Test exposing (Test, describe, test)


all : Test
all =
    describe "FilePath"
        [ joinTests
        , fromSegmentsTests
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


fromSegmentsTests : Test
fromSegmentsTests =
    describe "fromSegments"
        [ test "builds relative path" <|
            \() ->
                FilePath.fromSegments [ "usr", "bin" ]
                    |> FilePath.toString
                    |> Expect.equal "usr/bin"
        , test "leading empty string produces absolute path" <|
            \() ->
                FilePath.fromSegments [ "", "usr", "bin" ]
                    |> FilePath.toString
                    |> Expect.equal "/usr/bin"
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
