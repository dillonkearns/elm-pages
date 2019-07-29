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


preRenderRc : List PageOrPost -> String
preRenderRc content =
    interpolate """
  module.exports = {
  routes: [
  {0}
  ],
  rendererConfig: { renderAfterDocumentEvent: "prerender-trigger" }
};

"""
        [ prerenderPaths content ]


prerenderPaths content =
    content
        |> List.map prerenderRcFormattedPath
        |> List.map (\path -> String.concat [ "\"", path, "\"" ])
        |> String.join ", "


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


generate : List PageOrPost -> String
generate content =
    interpolate """module RawContent exposing (content)

import Pages.Content as Content exposing (Content)
import Dict exposing (Dict)
import Element exposing (Element)


content : List ( List String, String )
content =
    [
    {0}
    ]
"""
        [ List.map generatePage content |> String.join "\n  ,"
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
    { content : List PageOrPost, images : List String }


type alias PageOrPost =
    { path : String, contents : String }


init : Flags -> CliOptions -> Cmd Never
init flags Default =
    { rawContent =
        generate flags.content
    , prerenderrc = preRenderRc flags.content
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


main : Program.StatelessProgram Never Extras
main =
    Program.stateless
        { printAndExitFailure = printAndExitFailure
        , printAndExitSuccess = printAndExitSuccess
        , init = init
        , config = program
        }
