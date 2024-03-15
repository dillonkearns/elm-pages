module Which exposing (run)

import BackendTask exposing (BackendTask)
import Pages.Script as Script exposing (Script, doThen, sleep)
import Pages.Script.Spinner as Spinner


run : Script
run =
    Script.withoutCliOptions
        (Script.expectWhich "elm"
            |> BackendTask.andThen (\exe -> Script.sh (exe ++ " --version"))
            |> BackendTask.andThen
                (\elmVersion ->
                    if elmVersion == "0.19.1" then
                        Script.log "You are on the latest version of Elm!"

                    else
                        Script.log elmVersion
                )
            |> Script.doThen
                (Script.sh "elm diff"
                    |> BackendTask.map
                        (\_ ->
                            ()
                        )
                )
        )
