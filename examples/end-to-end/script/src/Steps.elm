module Steps exposing (run)

import BackendTask exposing (BackendTask)
import Pages.Script as Script exposing (Script, doThen, sleep)
import Pages.Script.Spinner as Spinner


run : Script
run =
    Script.withoutCliOptions
        (BackendTask.succeed
            (\spinner1 spinner2 spinner3 ->
                sleep 3000
                    |> Spinner.runTaskExisting spinner1
                    |> doThen
                        (sleep 3000
                            |> Spinner.runTaskExisting spinner2
                            |> doThen
                                (sleep 3000
                                    |> Spinner.runTaskExisting spinner3
                                )
                        )
            )
            |> BackendTask.andMap
                (Spinner.options "Step 1" |> Spinner.showStep)
            |> BackendTask.andMap
                (Spinner.options "Step 2" |> Spinner.showStep)
            |> BackendTask.andMap
                (Spinner.options "Step 3" |> Spinner.showStep)
            |> BackendTask.andThen identity
        )
