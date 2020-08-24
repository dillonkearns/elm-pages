module PathTests exposing (..)

import Expect exposing (Expectation)
import Test exposing (..)


type Path
    = Path String


fromList list =
    list
        |> String.join "/"
        |> Path


toRelative (Path path) =
    path


all : Test
all =
    only <|
        describe "Path"
            [ test "there is no content flash during hydration" <|
                \() ->
                    fromList [ "blog", "generate-files" ]
                        |> toRelative
                        |> Expect.equal "blog/generate-files"
            ]


normalizePath : String -> String
normalizePath pathString =
    let
        hasPrefix =
            String.startsWith "/" pathString

        hasSuffix =
            String.endsWith "/" pathString
    in
    if pathString == "" then
        pathString

    else
        String.concat
            [ if hasPrefix then
                String.dropLeft 1 pathString

              else
                pathString
            , if hasSuffix then
                ""

              else
                "/"
            ]
