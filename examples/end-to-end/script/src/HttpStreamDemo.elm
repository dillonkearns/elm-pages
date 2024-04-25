module Todo exposing (run)

import BackendTask
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.log "Just"
        |> BackendTask.andThen
            (\_ ->
                Debug.todo "Error string from todo."
            )
        |> Script.withoutCliOptions
