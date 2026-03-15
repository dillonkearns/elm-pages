module TestWithSchemaDebugLog exposing (run)

import BackendTask
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Debug
import Pages.Script as Script exposing (Script)
import TsJson.Encode as TsEncode


topLevelDebugLog : ()
topLevelDebugLog =
    Debug.log "top-level-debug-log" "initialized"
        |> (\_ -> ())


config =
    let
        _ =
            topLevelDebugLog
    in
    { description = "Test script with a top-level Debug.log"
    , cliOptions =
        Program.config
            |> Program.add
                (OptionsParser.build ())
    , encoder =
        TsEncode.object
            [ TsEncode.required "status"
                .status
                TsEncode.string
            ]
    , run =
        \() ->
            BackendTask.succeed
                { status = "ok" }
    }


run : Script
run =
    Script.withSchema config
