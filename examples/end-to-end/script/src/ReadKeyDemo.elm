module ReadKeyDemo exposing (run)

import BackendTask exposing (BackendTask)
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "Do you want to continue? [Y/n] "
            |> BackendTask.andThen (\_ -> Script.readKeyWithDefault "y")
            |> BackendTask.andThen
                (\key ->
                    case String.toLower key of
                        "y" ->
                            Script.log "\nContinuing!"

                        "n" ->
                            Script.log "\nAborting."

                        _ ->
                            Script.log ("\nUnrecognized key: '" ++ key ++ "'")
                )
        )
