port module Main exposing (generate)

import Cli.OptionsParser as OptionsParser exposing (with)
import Cli.Program as Program
import String.Interpolate exposing (interpolate)


port print : String -> Cmd msg


port printAndExitSuccess : String -> Cmd msg


port printAndExitFailure : String -> Cmd msg


generate =
    interpolate """

pages : List ( List String, String )
pages =
    [ ( [ {0} ]
      , \"\"\"|> Article
    author = Dillon Kearns
    title = Home Page
    tags = software other
    description =
        How I learned to use elm-markup.

This is the home page.
\"\"\"
      ) ]
posts :
    Result (List Mark.Error.Error)
        (List
            ( List String
            , { body : List (Element msg)
              , metadata : MarkParser.Metadata msg
              }
            )
        )
posts =
    [ ( [ "articles", "tiny-steps" ]
      , \"\"\"|> Article
    author = Dillon Kearns
    title = Tiny Steps
    tags = software other
    description =
        How I learned to use elm-markup.

  Here is an article.
  \"\"\"
      )
"""
        [ "\"\"" ]


type CliOptions
    = Default


program : Program.Config CliOptions
program =
    Program.config
        |> Program.add (OptionsParser.build Default)


type alias Flags =
    Program.FlagsIncludingArgv {}


init : Flags -> CliOptions -> Cmd Never
init flags Default =
    generate
        |> print


main : Program.StatelessProgram Never {}
main =
    Program.stateless
        { printAndExitFailure = printAndExitFailure
        , printAndExitSuccess = printAndExitSuccess
        , init = init
        , config = program
        }
