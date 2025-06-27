module TestScript exposing (run)

import Pages.Script


run : Pages.Script.Script
run =
    Pages.Script.log "Hello from TestScript"
        |> Pages.Script.withoutCliOptions
