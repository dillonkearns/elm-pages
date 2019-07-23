port module Main exposing (generate)

import Cli.OptionsParser as OptionsParser exposing (with)
import Cli.Program as Program
import String.Interpolate exposing (interpolate)


port print : String -> Cmd msg


port printAndExitSuccess : String -> Cmd msg


port printAndExitFailure : String -> Cmd msg


generatePage : String
generatePage =
    interpolate """( [ {0} ]
      , \"\"\"|> Article
    author = Dillon Kearns
    title = Home Page
    tags = software other
    description =
        How I learned to use elm-markup.

This is the home page.
\"\"\"
      )
"""
        [ "\"\"" ]


generate : String
generate =
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
        [ generatePage
        , generatePage
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
    generate
        |> print


main : Program.StatelessProgram Never Extras
main =
    Program.stateless
        { printAndExitFailure = printAndExitFailure
        , printAndExitSuccess = printAndExitSuccess
        , init = init
        , config = program
        }
