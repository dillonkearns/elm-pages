module ExampleScript exposing (fetchAndLogStars, fetchAndWriteReport, starsScript)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Pages.Script as Script


{-| Fetch the star count for a GitHub repo and log it.
-}
fetchAndLogStars : { username : String, repo : String } -> BackendTask FatalError ()
fetchAndLogStars { username, repo } =
    BackendTask.Http.getJson
        ("https://api.github.com/repos/" ++ username ++ "/" ++ repo)
        (Decode.field "stargazers_count" Decode.int)
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\stars ->
                Script.log (username ++ "/" ++ repo ++ " has " ++ String.fromInt stars ++ " stars")
            )


{-| Fetch stars for two repos and write a report file.
-}
fetchAndWriteReport : { username : String, repos : List String } -> BackendTask FatalError ()
fetchAndWriteReport { username, repos } =
    repos
        |> List.map
            (\repo ->
                BackendTask.Http.getJson
                    ("https://api.github.com/repos/" ++ username ++ "/" ++ repo)
                    (Decode.field "stargazers_count" Decode.int)
                    |> BackendTask.allowFatal
                    |> BackendTask.map (\stars -> repo ++ ": " ++ String.fromInt stars)
            )
        |> BackendTask.combine
        |> BackendTask.andThen
            (\lines ->
                Script.writeFile
                    { path = "report.md"
                    , body = "# Star Report\n\n" ++ String.join "\n" lines
                    }
                    |> BackendTask.allowFatal
            )


{-| A full Script value with CLI options for testing with fromScript.
-}
starsScript : Script.Script
starsScript =
    Script.withCliOptions
        (Program.config
            |> Program.add
                (OptionsParser.build
                    (\username repo -> { username = username, repo = repo })
                    |> OptionsParser.with
                        (Option.optionalKeywordArg "username"
                            |> Option.withDefault "dillonkearns"
                        )
                    |> OptionsParser.with
                        (Option.optionalKeywordArg "repo"
                            |> Option.withDefault "elm-pages"
                        )
                )
        )
        (\{ username, repo } ->
            fetchAndLogStars { username = username, repo = repo }
        )
