module GitDemo exposing (run)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Git
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Git.try Git.currentBranch
            |> BackendTask.andThen Script.log
        )
