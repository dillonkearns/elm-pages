module Test.Glob exposing (all)

import DataSource exposing (DataSource)
import DataSource.Glob as Glob exposing (Glob)
import DataSource.Internal.Glob


all : List (DataSource (Result String ()))
all =
    [ test
        { name = "1"
        , glob = findBySplat []
        , expected = [ "content/index.md" ]
        }
    , test
        { name = "2"
        , glob = findBySplat [ "foo" ]
        , expected = [ "content/foo/index.md" ]
        }
    , test
        { name = "3"
        , glob = findBySplat [ "bar" ]
        , expected = [ "content/bar.md" ]
        }
    , test
        { name = "4"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/content1/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.oneOf ( ( ".md", () ), [ ( "/", () ) ] ))
                |> Glob.match Glob.wildcard
        , expected = [ "about", "posts" ]
        }
    , test
        { name = "5"
        , glob =
            Glob.succeed
                (\first second wildcardPart ->
                    { first = first
                    , second = second
                    , wildcard = wildcardPart
                    }
                )
                |> Glob.capture (Glob.literal "glob-test-cases/")
                |> Glob.capture (Glob.literal "content1/")
                |> Glob.capture Glob.wildcard
        , expected =
            [ { first = "glob-test-cases/"
              , second = "content1/"
              , wildcard = "about.md"
              }
            ]
        }
    , test
        { name = "6"
        , glob =
            Glob.succeed Tuple.pair
                |> Glob.match (Glob.literal "glob-test-cases/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".")
                |> Glob.capture
                    (Glob.oneOf
                        ( ( "yml", YAML )
                        , [ ( "json", JSON )
                          ]
                        )
                    )
        , expected = [ ( "data-file", JSON ) ]
        }
    , test
        { name = "7"
        , glob =
            Glob.succeed
                (\year month day slug ->
                    { year = year
                    , month = month
                    , day = day
                    , slug = slug
                    }
                )
                |> Glob.match (Glob.literal "glob-test-cases/")
                |> Glob.match (Glob.literal "archive/")
                |> Glob.capture Glob.int
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.int
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.int
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".md")
        , expected =
            [ { day = 10
              , month = 6
              , year = 1977
              , slug = "apple-2-released"
              }
            ]
        }
    , test
        { name = "8"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/at-least-one/")
                |> Glob.match Glob.wildcard
                |> Glob.match (Glob.literal ".")
                |> Glob.capture
                    (Glob.atLeastOne
                        ( ( "yml", YAML )
                        , [ ( "json", JSON )
                          ]
                        )
                    )
        , expected = [ ( JSON, [ YAML, JSON, JSON ] ) ]
        }
    , testDir
        { name = "9"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/folder1/")
                |> Glob.capture Glob.recursiveWildcard
        , expectedDirs =
            [ [ "folder2a" ]
            , [ "folder2b" ]
            , [ "folder2a", "folder3a" ]
            , [ "folder2a", "folder3b" ]
            , [ "folder2b", "folder3" ]
            ]
        , expectedFiles = []
        }
    ]


findBySplat : List String -> Glob String
findBySplat splat =
    if splat == [] then
        Glob.literal "content/index.md"

    else
        Glob.succeed identity
            |> Glob.captureFilePath
            |> Glob.match (Glob.literal "content/")
            |> Glob.match (Glob.literal (String.join "/" splat))
            |> Glob.match
                (Glob.oneOf
                    ( ( "", () )
                    , [ ( "/index", () ) ]
                    )
                )
            |> Glob.match (Glob.literal ".md")


type JsonOrYaml
    = JSON
    | YAML


test : { name : String, glob : Glob value, expected : List value } -> DataSource (Result String ())
test { glob, name, expected } =
    Glob.toDataSource glob
        |> DataSource.map
            (\actual ->
                if actual == expected then
                    Ok ()

                else
                    Err <|
                        name
                            ++ " failed\nPattern: `"
                            ++ DataSource.Internal.Glob.toPattern glob
                            ++ "`\nExpected\n"
                            ++ Debug.toString expected
                            ++ "\nActual\n"
                            ++ Debug.toString actual
            )


testDir :
    { name : String
    , glob : Glob value
    , expectedDirs : List value
    , expectedFiles : List value
    }
    -> DataSource (Result String ())
testDir { glob, name, expectedDirs, expectedFiles } =
    Glob.listDirectories glob
        |> DataSource.map
            (\actual ->
                if actual == expectedDirs then
                    Ok ()

                else
                    Err <|
                        name
                            ++ " failed\nPattern: `"
                            ++ DataSource.Internal.Glob.toPattern glob
                            ++ "`\nExpected\n"
                            ++ Debug.toString expectedDirs
                            ++ "\nActual\n"
                            ++ Debug.toString actual
            )
