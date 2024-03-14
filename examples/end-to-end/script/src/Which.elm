module Which exposing (run)

import BackendTask exposing (BackendTask)
import Pages.Script as Script exposing (Script, doThen, sleep)
import Pages.Script.Spinner as Spinner


run : Script
run =
    Script.withoutCliOptions
        (Script.expectWhich "elm"
            |> BackendTask.andThen
                (\elmPath ->
                    Script.log elmPath
                )
        )
