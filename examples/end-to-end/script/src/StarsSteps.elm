module StarsSteps exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Json.Decode as Decode
import Pages.Script as Script exposing (Script, doThen)
import Pages.Script.Spinner as Spinner


run : Script
run =
    Script.withCliOptions program
        (\{ username, repo } ->
            (Script.sleep 3000
                |> doThen
                    (BackendTask.Http.getJson
                        ("https://api.github.com/repos/dillonkearns/" ++ repo)
                        (Decode.field "stargazers_count" Decode.int)
                    )
            )
                |> Spinner.runTaskWithOptions
                    (Spinner.options "Fetching stars"
                        |> Spinner.withOnCompletion
                            (\result ->
                                case result of
                                    Ok _ ->
                                        ( Spinner.Succeed, Nothing )

                                    Err _ ->
                                        ( Spinner.Fail
                                        , Just "Uh oh! Failed to fetch"
                                        )
                            )
                    )
                |> BackendTask.andThen
                    (\stars ->
                        Script.sleep 3000
                            |> doThen
                                (BackendTask.Http.getJson
                                    ("https://api.github.com/repos/dillonkearnz/" ++ repo)
                                    (Decode.field "stargazers_count" Decode.int)
                                    |> BackendTask.andThen
                                        (\_ ->
                                            Script.log (String.fromInt stars)
                                        )
                                )
                            |> Spinner.runTaskWithOptions
                                (Spinner.options "Fetching invalid..."
                                    |> Spinner.withOnCompletion
                                        (\result ->
                                            case result of
                                                Ok _ ->
                                                    ( Spinner.Succeed, Nothing )

                                                Err _ ->
                                                    ( Spinner.Fail
                                                    , Just "Uh oh! Failed to fetch"
                                                    )
                                        )
                                )
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
