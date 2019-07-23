port module Main exposing (generate)

import Cli.OptionsParser as OptionsParser exposing (with)
import Cli.Program as Program
import String.Interpolate exposing (interpolate)


port writeFile : String -> Cmd msg


port printAndExitSuccess : String -> Cmd msg


port printAndExitFailure : String -> Cmd msg


generatePage : PageOrPost -> String
generatePage pageOrPost =
    interpolate """( {0}
      , \"\"\"{1}\"\"\"
      )
"""
        [ pathFor pageOrPost
        , pageOrPost.contents
        ]


pathFor : PageOrPost -> String
pathFor pageOrPost =
    pageOrPost.path
        |> String.dropRight 4
        |> String.split "/"
        |> List.drop 1
        |> List.map (\pathPart -> String.concat [ "\"", pathPart, "\"" ])
        |> String.join ", "
        |> (\list -> String.concat [ "[", list, "]" ])


generate : { posts : List PageOrPost, pages : List PageOrPost } -> String
generate content =
    interpolate """module RawContent exposing (content)

import Content exposing (Content)
import Element exposing (Element)


content : Result (Element msg) (Content msg)
content =
    Content.buildAllData { pages = pages, posts = posts }


pages : List ( List String, String )
pages =
    [
    {0}
    ]


posts : List ( List String, String )
posts =
    [
    {1}
    ]
"""
        [ List.map generatePage content.pages |> String.join "\n  ,"
        , List.map generatePage content.posts |> String.join "\n  ,"
        ]


type CliOptions
    = Default


program : Program.Config CliOptions
program =
    Program.config
        |> Program.add (OptionsParser.build Default)


type alias Flags =
    Program.FlagsIncludingArgv Extras


type alias Extras =
    { posts : List PageOrPost, pages : List PageOrPost }


type alias PageOrPost =
    { path : String, contents : String }


init : Flags -> CliOptions -> Cmd Never
init flags Default =
    generate { pages = flags.pages, posts = flags.posts }
        |> writeFile


main : Program.StatelessProgram Never Extras
main =
    Program.stateless
        { printAndExitFailure = printAndExitFailure
        , printAndExitSuccess = printAndExitSuccess
        , init = init
        , config = program
        }
