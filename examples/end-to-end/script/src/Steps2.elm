module Steps2 exposing (run)

import BackendTask exposing (BackendTask)
import Pages.Script as Script exposing (Script, doThen, sleep)
import Pages.Script.Spinner as Spinner


run : Script
run =
    Script.withoutCliOptions
        (Spinner.steps
            |> Spinner.withStep "Step 1" (\() -> sleep 3000)
            |> Spinner.withStep "Step 2" (\() -> sleep 3000)
            |> Spinner.withStep "Step 3" (\() -> sleep 3000)
            |> Spinner.runSteps
        )
