module TestListFiles exposing (run)

import BackendTask
import BackendTask.Glob as Glob
import Cli.Option.Typed as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Pages.Script as Script exposing (Script)
import TsJson.Encode as TsEncode


config =
    { description = "List Elm source files in a directory"
    , cliOptions =
        Program.config
            |> Program.add
                (OptionsParser.build identity
                    |> OptionsParser.with
                        (Option.optionalKeywordArg "dir" Option.string)
                )
    , encoder =
        TsEncode.object
            [ TsEncode.required "files"
                .files
                (TsEncode.list TsEncode.string)
            , TsEncode.required "count"
                .count
                TsEncode.int
            ]
    , run =
        \maybeDir ->
            let
                dir =
                    maybeDir
                        |> Maybe.withDefault "src"
            in
            Glob.succeed identity
                |> Glob.match (Glob.literal (dir ++ "/"))
                |> Glob.capture Glob.wildcard
                |> Glob.match (Glob.literal ".elm")
                |> Glob.toBackendTask
                |> BackendTask.allowFatal
                |> BackendTask.map
                    (\files ->
                        { files = List.map (\f -> f ++ ".elm") files
                        , count = List.length files
                        }
                    )
    }


run : Script
run =
    Script.withSchema config
