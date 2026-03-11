module TestWithSchema exposing (run, schemaInfo)

import BackendTask
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Json.Encode
import Pages.Script as Script exposing (Script)
import TsJson.Encode as TsEncode


config =
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


run : Script
run =
    Script.withSchema config


schemaInfo : { moduleName : String, path : String } -> Json.Encode.Value
schemaInfo =
    Script.introspect config
