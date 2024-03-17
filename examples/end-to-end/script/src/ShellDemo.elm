module ShellDemo exposing (run)

import BackendTask exposing (BackendTask)
import Pages.Script as Script exposing (Script)
import Shell


run : Script
run =
    Script.withoutCliOptions
        (Shell.command "elm" [ "diff" ]
            |> Shell.pipe (Shell.command "wc" [ "-l" ])
            |> Shell.stdout
            |> BackendTask.andThen Script.log
        )
