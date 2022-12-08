module RepeatLog exposing (run)

import DataSource
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "-> 1"
            |> DataSource.andThen
                (\_ ->
                    Script.log "-> 1"
                        |> DataSource.andThen
                            (\_ ->
                                Script.log "-> 1"
                                    |> DataSource.andThen
                                        (\_ ->
                                            Script.log "-> 1"
                                        )
                            )
                )
        )
