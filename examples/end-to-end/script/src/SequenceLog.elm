module SequenceLog exposing (run)

import BackendTask
import BackendTask.Http
import Json.Decode as Decode
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "-> 1"
            |> BackendTask.andThen
                (\_ ->
                    Script.log "-> 2"
                        |> BackendTask.andThen
                            (\_ ->
                                Script.log "-> 3"
                                    |> BackendTask.andThen
                                        (\_ ->
                                            Script.log "-> 4"
                                        )
                            )
                )
        )
