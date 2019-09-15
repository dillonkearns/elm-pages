module Example exposing (..)

import Expect exposing (Expectation)
import Pages.Directory as Directory exposing (Directory)
import Pages.PagePath as PagePath exposing (PagePath)
import Test exposing (..)


suite : Test
suite =
    describe "includes"
        [ test "directory with single file" <|
            \() ->
                quickStart
                    |> Directory.includes (Directory.build () [ quickStart ] [ "docs" ])
                    |> Expect.equal True
        , test "directory with two files" <|
            \() ->
                quickStart
                    |> Directory.includes (Directory.build () [ performance, quickStart ] [ "docs" ])
                    |> Expect.equal True
        , test "file in different directory" <|
            \() ->
                notInDocsDir
                    |> Directory.includes (Directory.build () [ performance, quickStart, notInDocsDir ] [ "docs" ])
                    |> Expect.equal False
        ]


quickStart =
    PagePath.build () [ "docs", "quick-start" ]


performance =
    PagePath.build () [ "docs", "performance" ]


notInDocsDir =
    PagePath.build () [ "notInDocsDir" ]
