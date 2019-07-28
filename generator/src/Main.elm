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
import Dict exposing (Dict)
import Element exposing (Element)


content : List ( List String, String )
content =
    [
    {0}
    ]
"""
        [ List.map generatePage (content.pages ++ content.posts) |> String.join "\n  ,"
        ]


type CliOptions
    = Default


program : Program.Config CliOptions
program =
    Program.config
        |> Program.add (OptionsParser.build Default)


type alias Flags =
    Program.FlagsIncludingArgv { posts : List PageOrPost, pages : List PageOrPost, images : List String }


type alias Extras =
    { posts : List PageOrPost, pages : List PageOrPost }


type alias PageOrPost =
    { path : String, contents : String }


init : Flags -> CliOptions -> Cmd Never
init flags Default =
    { rawContent =
        generate { pages = flags.pages, posts = flags.posts }
    , prerenderrc = preRenderRc { pages = flags.pages, posts = flags.posts }
    , imageAssets = imageAssetsFile flags.images
    }
        |> writeFile


imageAssetsFile : List String -> String
imageAssetsFile images =
    interpolate """export const imageAssets = {
  {0}
};
"""
        [ images |> List.map imageAssetEntry |> String.join ",\n  " ]


imageAssetEntry : String -> String
imageAssetEntry string =
    interpolate """"{0}": require("{1}")"""
        [ string |> String.dropLeft 7
        , "../../" ++ string
        ]


main : Program.StatelessProgram Never { posts : List PageOrPost, pages : List PageOrPost, images : List String }
main =
    Program.stateless
        { printAndExitFailure = printAndExitFailure
        , printAndExitSuccess = printAndExitSuccess
        , init = init
        , config = program
        }
