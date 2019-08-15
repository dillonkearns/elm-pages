port module Main exposing (main)

import Cli.Option as Option
import Cli.OptionsParser as OptionsParser exposing (with)
import Cli.Program as Program
import List.Extra
import String.Interpolate exposing (interpolate)


port writeFile :
    { rawContent : String
    , routes : List String
    , imageAssets : String
    , watch : Bool
    , debug : Bool
    }
    -> Cmd msg


port printAndExitSuccess : String -> Cmd msg


port printAndExitFailure : String -> Cmd msg


generatePage : Page -> String
generatePage page =
    interpolate """( {0}
      , \"\"\"{1}\"\"\"
      )
"""
        [ pathFor page
        , page.contents
        ]


prerenderRcFormattedPath : String -> String
prerenderRcFormattedPath path =
    path
        |> dropExtension
        |> String.split "/"
        |> dropIndexFromLast
        |> List.drop 1
        |> String.join "/"
        |> (\pathSoFar -> "/" ++ pathSoFar)


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


allRoutes : List String -> List String
allRoutes paths =
    paths
        |> List.map prerenderRcFormattedPath


pathFor : { entry | path : String } -> String
pathFor page =
    page.path
        |> dropExtension
        |> String.split "/"
        |> List.drop 1
        |> dropIndexFromLast
        |> List.map (\pathPart -> String.concat [ "\"", pathPart, "\"" ])
        |> String.join ", "
        |> (\list -> String.concat [ "[", list, "]" ])


dropExtension : String -> String
dropExtension path =
    if path |> String.endsWith ".emu" then
        path |> String.dropRight 4

    else if path |> String.endsWith ".md" then
        path |> String.dropRight 3

    else
        path


generate : List Page -> List MarkdownContent -> String
generate content markdownContent =
    interpolate """module RawContent exposing (content)

import Pages.Content as Content exposing (Content)
import Dict exposing (Dict)
import Element exposing (Element)


content : { markdown : List ( List String, { frontMatter : String, body : String } ), markup : List ( List String, String ) }
content =
    { markdown = markdown, markup = markup }


markdown : List ( List String, { frontMatter : String, body : String } )
markdown =
    [ {1}
    ]


markup : List ( List String, String )
markup =
    [
    {0}
    ]
"""
        [ List.map generatePage content |> String.join "\n  ,"
        , List.map generateMarkdownPage markdownContent |> String.join "\n  ,"
        ]


isFrontmatterDelimeter : Maybe String -> Bool
isFrontmatterDelimeter line =
    line == Just "---"


splitMarkdown : String -> ( String, String )
splitMarkdown contents =
    let
        lines =
            contents
                |> String.lines
    in
    if lines |> List.head |> isFrontmatterDelimeter then
        splitAtClosingDelimeter (lines |> List.drop 1)

    else
        ( "", lines |> String.join "\n" )


splitAtClosingDelimeter : List String -> ( String, String )
splitAtClosingDelimeter lines =
    List.Extra.splitWhen (\line -> line == "---") lines
        |> Maybe.map (Tuple.mapSecond (List.drop 1))
        |> Maybe.withDefault ( [], [] )
        |> Tuple.mapBoth (String.join "\n") (String.join "\n")


generateMarkdownPage : MarkdownContent -> String
generateMarkdownPage markdown =
    let
        ( frontmatter, body ) =
            ( markdown.metadata, markdown.body )
    in
    interpolate """( {0}
  , { frontMatter = \"\"\" {1}
\"\"\"
    , body = \"\"\"{2}\"\"\" }
  )
"""
        [ pathFor markdown
        , frontmatter
        , body
        ]


type CliOptions
    = Develop { debugger : Bool }
    | Build


application : Program.Config CliOptions
application =
    Program.config
        |> Program.add
            (OptionsParser.buildSubCommand "develop"
                (\debugger ->
                    Develop { debugger = debugger }
                )
                |> with (Option.flag "debug")
            )
        |> Program.add
            (OptionsParser.buildSubCommand "build" Build)


type alias Flags =
    Program.FlagsIncludingArgv Extras


type alias Extras =
    { content : List Page, markdownContent : List MarkdownContent, images : List String }


type alias Page =
    { path : String, contents : String }


type alias MarkdownContent =
    { path : String, metadata : String, body : String }


init : Flags -> CliOptions -> Cmd Never
init flags cliOptions =
    let
        ( watch, debug ) =
            case cliOptions of
                Develop options ->
                    ( True, options.debugger )

                Build ->
                    ( False, False )
    in
    { rawContent =
        generate flags.content flags.markdownContent
    , routes = allRoutes (List.map .path flags.content ++ List.map .path flags.markdownContent)
    , imageAssets = imageAssetsFile flags.images
    , watch = watch
    , debug = debug
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
        , config = application
        }
