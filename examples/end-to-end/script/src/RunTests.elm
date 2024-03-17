module ShellDemo exposing (run)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Git
import Json.Decode as Decode
import Pages.Script as Script exposing (Script)
import Shell exposing (command)


run : Script
run =
    Script.withoutCliOptions
        (Shell.command "elm-outdated" []
            |> Shell.pipe (Shell.command "cat" [])
            --|> Shell.pipe (Shell.command "wc" [ "-l" ])
            |> Shell.map
                (\output ->
                    ((output
                        |> String.trimRight
                        |> String.lines
                        |> List.length
                     )
                        - 1
                    )
                        |> String.fromInt
                )
            |> Shell.stdout
            |> BackendTask.andThen Script.log
        )
