module MyCli exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Json.Decode as Decode
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withCliOptions program
        (\{ username, repo } ->
            BackendTask.Http.get
                ("https://api.github.com/repos/" ++ username ++ "/" ++ repo)
                (Decode.field "stargazers_count" Decode.int)
                |> BackendTask.andThen
                    (\stars ->
                        Script.log (String.fromInt stars)
                    )
                |> BackendTask.allowFatal
        )


type alias CliOptions =
    { username : String
    , repo : String
    }


program : Program.Config CliOptions
program =
    Program.config
        |> Program.add
            (OptionsParser.build CliOptions
                |> OptionsParser.with
                    (Option.optionalKeywordArg "username" |> Option.withDefault "dillonkearns")
                |> OptionsParser.with
                    (Option.optionalKeywordArg "repo" |> Option.withDefault "elm-pages")
            )
