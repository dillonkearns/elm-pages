module RepeatLog exposing (run)

import BackendTask
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "-> 1"
            |> BackendTask.andThen
                (\_ ->
                    Script.log "-> 1"
                        |> BackendTask.andThen
                            (\_ ->
                                Script.log "-> 1"
                                    |> BackendTask.andThen
                                        (\_ ->
                                            Script.log "-> 1"
                                        )
                            )
                )
        )
