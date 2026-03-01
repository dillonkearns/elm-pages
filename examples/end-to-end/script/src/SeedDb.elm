module SeedDb exposing (run)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Pages.Db
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Pages.Db.update
            (\db ->
                { db
                    | todos =
                        [ { id = 1, title = "Buy milk", completed = False }
                        , { id = 2, title = "Write tests", completed = True }
                        , { id = 3, title = "Ship feature", completed = False }
                        ]
                    , nextId = 4
                }
            )
            |> BackendTask.andThen (\_ -> Script.log "Seeded db.bin with 3 todos.")
        )
