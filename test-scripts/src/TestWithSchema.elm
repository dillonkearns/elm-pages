module TestWithSchema exposing (run)

import BackendTask
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Pages.Script as Script exposing (Script)
import TsJson.Encode as TsEncode


run : Script
run =
    Script.withSchema
        { description = "Test script for withSchema smoke test"
        , cliOptions =
            Program.config
                |> Program.add
                    (OptionsParser.build identity
                        |> OptionsParser.with
                            (Option.requiredKeywordArg "name")
                    )
        , encoder =
            TsEncode.object
                [ TsEncode.required "greeting"
                    .greeting
                    TsEncode.string
                ]
        , run =
            \name ->
                BackendTask.succeed
                    { greeting = "Hello, " ++ name ++ "!" }
        }
