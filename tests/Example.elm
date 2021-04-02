module Example exposing (..)

import Expect
import Pages.Directory as Directory
import Pages.PagePath as PagePath
import Test exposing (..)


suite : Test
suite =
    describe "includes"
        [ test "directory with single file" <|
            \() ->
                quickStart
                    |> Directory.includes (Directory.withIndex () [ quickStart ] [ "docs" ])
                    |> Expect.equal True
        , test "directory with two files" <|
            \() ->
                quickStart
                    |> Directory.includes (Directory.withIndex () [ performance, quickStart ] [ "docs" ])
                    |> Expect.equal True
        , test "file in different directory" <|
            \() ->
                notInDocsDir
                    |> Directory.includes (Directory.withIndex () [ performance, quickStart, notInDocsDir ] [ "docs" ])
                    |> Expect.equal False
        , test "index file is in the directory of the same name" <|
            \() ->
                docsIndex
                    |> Directory.includes (Directory.withIndex () [ performance, quickStart, notInDocsDir, docsIndex ] [ "docs" ])
                    |> Expect.equal True
        ]


quickStart =
    PagePath.build () [ "docs", "quick-start" ]


performance =
    PagePath.build () [ "docs", "performance" ]


docsIndex =
    PagePath.build () [ "docs" ]


notInDocsDir =
    PagePath.build () [ "notInDocsDir" ]
