port module Main exposing (main)

import Cli.Option as Option
import Cli.OptionsParser as OptionsParser exposing (with)
import Cli.Program as Program
import Json.Encode as Encode
import List.Extra
import String.Interpolate exposing (interpolate)


port writeFile : Encode.Value -> Cmd msg


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
        |> chopForwardSlashes
        |> String.split "/"
        |> dropIndexFromLast
        |> String.join "/"


dropIndexFromLast : List String -> List String
dropIndexFromLast path =
    path
        |> List.reverse
        |> (\reversePath ->
                case List.head reversePath of
                    Just "index" ->
                        List.drop 1 reversePath

                    _ ->
                        reversePath
           )
        |> List.reverse


chopForwardSlashes : String -> String
chopForwardSlashes =
    String.split "/" >> List.filter ((/=) "") >> String.join "/"


pathFor : { entry | path : String } -> String
pathFor page =
    page.path
        |> dropExtension
        |> chopForwardSlashes
        |> String.split "/"
        |> dropIndexFromLast
        |> List.map (\pathPart -> String.concat [ "\"", pathPart, "\"" ])
        |> String.join ", "
        |> (\list -> String.concat [ "[", list, "]" ])


dropExtension : String -> String
dropExtension path =
    if String.endsWith ".emu" path then
        String.dropRight 4 path

    else if String.endsWith ".md" path then
        String.dropRight 3 path

    else
        path


generate : List Page -> List MarkdownContent -> String
generate content markdownContent =
    interpolate """module RawContent exposing (content)

import Dict exposing (Dict)


content : { markdown : List ( List String, { frontMatter : String, body : Maybe String } ), markup : List ( List String, String ) }
content =
    { markdown = markdown }


markdown : List ( List String, { frontMatter : String, body : Maybe String } )
markdown =
    [ {1}
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
    , body = Nothing }
  )
"""
        [ pathFor markdown
        , frontmatter
        , body
        ]


type CliOptions
    = Develop DevelopOptions
    | Build
    | Generate


type alias DevelopOptions =
    { debugger : Bool
    , customPort : Maybe Int
    }


application : Program.Config CliOptions
application =
    Program.config
        |> Program.add
            (OptionsParser.buildSubCommand "develop" DevelopOptions
                |> OptionsParser.withDoc "you can set the port with --port=3200"
                |> with (Option.flag "debug")
                |> with
                    (Option.optionalKeywordArg "port"
                        |> Option.validateMapIfPresent (String.toInt >> Result.fromMaybe "port needs to be an integer")
                    )
                |> OptionsParser.map Develop
            )
        |> Program.add
            (OptionsParser.buildSubCommand "build" Build)
        |> Program.add
            (OptionsParser.buildSubCommand "generate" Generate)


type alias Flags =
    Program.FlagsIncludingArgv Extras


type alias Extras =
    {}


type alias Page =
    { path : String, contents : String }


type alias MarkdownContent =
    { path : String, metadata : String, body : String }


type DevelopMode
    = None
    | Run
    | Start


init : Flags -> CliOptions -> Cmd Never
init flags cliOptions =
    let
        ( develop, debug, customPort ) =
            case cliOptions of
                Develop options ->
                    ( Start, options.debugger, options.customPort )

                Build ->
                    ( Run, False, Nothing )

                Generate ->
                    ( None, False, Nothing )
    in
    { develop = develop
    , debug = debug
    , customPort = customPort
    }
        |> encodeWriteFile
        |> writeFile


encodeWriteFile : { develop : DevelopMode, debug : Bool, customPort : Maybe Int } -> Encode.Value
encodeWriteFile { develop, debug, customPort } =
    Encode.object
        [ ( "develop", encodeDevelop develop )
        , ( "debug", Encode.bool debug )
        , ( "customPort", encodeCustomPort customPort )
        ]


encodeDevelop : DevelopMode -> Encode.Value
encodeDevelop develop =
    case develop of
        None ->
            Encode.string "none"

        Run ->
            Encode.string "run"

        Start ->
            Encode.string "start"


encodeCustomPort : Maybe Int -> Encode.Value
encodeCustomPort maybePort =
    maybePort
        |> Maybe.map Encode.int
        |> Maybe.withDefault Encode.null


generateFileContents : List MarkdownContent -> List ( String, String )
generateFileContents =
    List.map
        (\file ->
            ( prerenderRcFormattedPath file.path
            , file.body
            )
        )


main : Program.StatelessProgram Never Extras
main =
    Program.stateless
        { printAndExitFailure = printAndExitFailure
        , printAndExitSuccess = printAndExitSuccess
        , init = init
        , config = application
        }
