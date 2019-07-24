port module Main exposing (main)

import Cli.OptionsParser as OptionsParser exposing (with)
import Cli.Program as Program
import String.Interpolate exposing (interpolate)


port writeFile : { rawContent : String, prerenderrc : String, imageAssets : String } -> Cmd msg


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


prerenderRcFormattedPath : PageOrPost -> String
prerenderRcFormattedPath pageOrPost =
    pageOrPost.path
        |> String.dropRight 4
        |> String.split "/"
        |> dropIndexFromLast
        |> List.drop 1
        |> String.join "/"
        |> (\path -> "/" ++ path)


dropIndexFromLast : List String -> List String
dropIndexFromLast path =
    path
        |> List.reverse
        |> (\reversePath ->
                case List.head reversePath of
                    Just "index" ->
                        reversePath |> List.drop 1

                    _ ->
                        reversePath
           )
        |> List.reverse


preRenderRc : Extras -> String
preRenderRc extras =
    (extras.pages ++ extras.posts)
        |> List.map prerenderRcFormattedPath
        |> List.map (\path -> String.concat [ "\"", path, "\"" ])
        |> String.join ", "
        |> (\paths -> String.concat [ "[", paths, "]\n" ])


pathFor : PageOrPost -> String
pathFor pageOrPost =
    pageOrPost.path
        |> String.dropRight 4
        |> String.split "/"
        |> List.drop 1
        |> dropIndexFromLast
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
    { rawContent =
        generate { pages = flags.pages, posts = flags.posts }
    , prerenderrc = preRenderRc { pages = flags.pages, posts = flags.posts }
    , imageAssets = """export const imageAssets = {
  "dillon2.jpg": require("../../images/dillon2.jpg"),
  "article-cover/exit.jpg": require("../../images/article-cover/exit.jpg"),
  "article-cover/mountains.jpg": require("../../images/article-cover/mountains.jpg"),
  "article-cover/thinker.jpg": require("../../images/article-cover/thinker.jpg")
};
"""
    }
        |> writeFile


main : Program.StatelessProgram Never Extras
main =
    Program.stateless
        { printAndExitFailure = printAndExitFailure
        , printAndExitSuccess = printAndExitSuccess
        , init = init
        , config = program
        }
