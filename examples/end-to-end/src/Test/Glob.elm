module Test.Glob exposing (all)

import BackendTask exposing (BackendTask)
import BackendTask.Glob as Glob exposing (Glob, Include(..), defaultOptions)
import Expect
import Test exposing (Test, describe, test)


all : BackendTask error Test
all =
    [ globTestCase
        { name = "1"
        , glob = findBySplat []
        , expected = [ "content/index.md" ]
        }
    , globTestCase
        { name = "2"
        , glob = findBySplat [ "foo" ]
        , expected = [ "content/foo/index.md" ]
        }
    , globTestCase
        { name = "3"
        , glob = findBySplat [ "bar" ]
        , expected = [ "content/bar.md" ]
        }
    , globTestCase
        { name = "4"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/content1/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.oneOf ( ( ".md", () ), [ ( "/", () ) ] ))
                |> Glob.match Glob.wildcard
        , expected = [ "about", "posts" ]
        }
    , globTestCase
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
    , globTestCase
        { name = "capture"
        , glob =
            Glob.succeed identity
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".md")
        , expected = [ "README" ]
        }
    , globTestCase
        { name = "oneOf"
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
    , globTestCase
        { name = "multiple wildcards"
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
    , globTestCase
        { name = "atLeastOne"
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
    , globTestCase
        { name = "wildcard and map"
        , glob =
            Glob.succeed Tuple.pair
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal "/")
                |> Glob.capture (Glob.wildcard |> Glob.map String.toUpper)
                |> Glob.match (Glob.literal ".txt")
        , expected =
            [ ( "glob-test-cases", "FILE-1-2-3" )
            , ( "glob-test-cases", "FILE1" )
            ]
        }
    , globTestCase
        { name = "another map example"
        , glob =
            let
                expectDateFormat : List String -> Result String String
                expectDateFormat dateParts =
                    case dateParts of
                        [ year, month, date ] ->
                            Ok (String.join "-" [ year, month, date ])

                        _ ->
                            Err "Unexpected date format, expected yyyy/mm/dd folder structure."
            in
            Glob.succeed
                (\dateResult slug ->
                    dateResult
                        |> Result.map (\okDate -> ( okDate, slug ))
                )
                |> Glob.match (Glob.literal "glob-test-cases/blog/")
                |> Glob.capture (Glob.recursiveWildcard |> Glob.map expectDateFormat)
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".md")
        , expected =
            [ Ok ( "2021-05-28", "first-post" )
            , Err "Unexpected date format, expected yyyy/mm/dd folder structure."
            ]
        }
    , globTestCase
        { name = "literal root file"
        , glob =
            Glob.succeed identity
                |> Glob.capture (Glob.literal "README.md")
        , expected =
            [ "README.md" ]
        }
    , globTestCase
        { name = "withFilePath"
        , glob =
            Glob.succeed identity
                |> Glob.captureFilePath
                |> Glob.match Glob.wildcard
                |> Glob.match (Glob.literal ".txt")
        , expected =
            [ "greeting.txt" ]
        }
    , globTestCase
        { name = "wildcard and recursiveWildcard in one pattern"
        , glob =
            Glob.succeed Tuple.pair
                |> Glob.match (Glob.literal "glob-test-cases/content/")
                |> Glob.capture Glob.recursiveWildcard
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".md")
        , expected =
            [ ( [], "about" )
            , ( [ "community" ], "meetups" )
            ]
        }
    , globTestCase
        { name = "mix of match and capture with wildcards"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/mix/")
                |> Glob.match Glob.wildcard
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.wildcard
        , expected =
            [ "capture" ]
        }
    , globTestCase
        { name = "reversed mix of capture and wildcards"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/mix/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal "/")
                |> Glob.match Glob.wildcard
        , expected =
            [ "match" ]
        }
    , globTestCase
        { name = "recursive match"
        , glob =
            Glob.succeed Tuple.pair
                |> Glob.match (Glob.literal "glob-test-cases/recursive/")
                |> Glob.capture Glob.recursiveWildcard
                |> Glob.match (Glob.literal "/")
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".txt")
        , expected =
            [ ( [ "a", "b", "c" ], "d" )
            ]
        }
    , globTestCase
        { name = "zeroOrMore"
        , glob =
            Glob.succeed identity
                |> Glob.match (Glob.literal "glob-test-cases/zero-or-more/test/a")
                |> Glob.capture (Glob.zeroOrMore [ "a", "b" ])
                |> Glob.match (Glob.literal "/x.js")
        , expected =
            [ Nothing
            , Just "b"
            , Just "ba"
            ]
        }
    ]
        |> BackendTask.combine
        |> BackendTask.map (describe "glob tests")


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


globTestCase : { name : String, glob : Glob value, expected : List value } -> BackendTask error Test
globTestCase { glob, name, expected } =
    Glob.toBackendTask glob
        |> BackendTask.map
            (\actual ->
                test name <|
                    \() ->
                        actual
                            |> List.sortBy Debug.toString
                            |> Expect.equalLists
                                (expected
                                    |> List.sortBy Debug.toString
                                )
             --if actual == expected then
             --    --Ok ()
             --
             --else
             --    Err <|
             --        name
             --            ++ " failed\nPattern: `"
             --            ++ BackendTask.Internal.Glob.toPattern glob
             --            ++ "`\nExpected\n"
             --            ++ Debug.toString expected
             --            ++ "\nActual\n"
             --            ++ Debug.toString actual
            )


testDir :
    { name : String
    , glob : Glob value
    , expectedDirs : List value
    , expectedFiles : List value
    }
    -> BackendTask error Test
testDir { glob, name, expectedDirs, expectedFiles } =
    glob
        |> Glob.toBackendTaskWithOptions
            { defaultOptions
                | include = OnlyFolders
            }
        |> BackendTask.map
            (\actual ->
                test name <|
                    \() ->
                        actual
                            |> List.sortBy Debug.toString
                            |> Expect.equalLists
                                (expectedDirs
                                    |> List.sortBy Debug.toString
                                )
             --if actual == expectedDirs then
             --    Ok ()
             --
             --else
             --    Err <|
             --        name
             --            ++ " failed\nPattern: `"
             --            ++ BackendTask.Internal.Glob.toPattern glob
             --            ++ "`\nExpected\n"
             --            ++ Debug.toString expectedDirs
             --            ++ "\nActual\n"
             --            ++ Debug.toString actual
            )
