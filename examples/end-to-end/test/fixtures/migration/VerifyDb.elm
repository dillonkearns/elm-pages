module VerifyDb exposing (run)

import BackendTask
import Db
import FatalError exposing (FatalError)
import Pages.Db
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Pages.Db.get Pages.Db.default
            |> BackendTask.andThen
                (\db ->
                    if List.length db.todos == 3 then
                        Script.log "Migration verified: 3 todos preserved"

                    else
                        BackendTask.fail
                            (FatalError.build
                                { title = "Migration verification failed"
                                , body = "Expected 3 todos but got " ++ String.fromInt (List.length db.todos)
                                }
                            )
                )
        )
