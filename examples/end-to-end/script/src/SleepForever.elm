module SleepForever exposing (run)

import BackendTask
import BackendTask.Stream as Stream
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "Starting sleep..."
            |> BackendTask.andThen
                (\_ ->
                    Stream.command "sleep" [ "31415" ]
                        |> Stream.run
                )
        )
