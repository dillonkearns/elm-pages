module SequentialSteps exposing (run)

import Pages.Script as Script exposing (Script, doThen, sleep)
import Pages.Script.Spinner as Spinner


run : Script
run =
    Script.withoutCliOptions
        (sleep 3000
            |> Spinner.runTask "Step 1..."
            |> doThen
                (sleep 3000
                    |> Spinner.runTask "Step 2..."
                    |> doThen
                        (sleep 3000
                            |> Spinner.runTask "Step 3..."
                        )
                )
        )
