module Main exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Custom
import FatalError exposing (FatalError)
import Json.Decode
import Json.Encode
import Pages.Script as Script exposing (Script)


run : Script
run =
    BackendTask.Custom.run "environmentVariable"
        (Json.Encode.object [ ( "mutable", Json.Encode.int 0 ) ])
        Json.Decode.string
        |> BackendTask.allowFatal
        |> BackendTask.andThen Script.log
        |> Script.withoutCliOptions
