module ExampleScript exposing (fetchAndLogStars, fetchAndWriteReport, fetchWriteAndVerify, reportScript, starsScript)

import BackendTask exposing (BackendTask)
import BackendTask.File
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


{-| Fetch stars, write a report, read it back, and log a summary.
Exercises the write-then-read round trip through the virtual filesystem.
-}
fetchWriteAndVerify : { username : String, repos : List String } -> BackendTask FatalError ()
fetchWriteAndVerify { username, repos } =
    fetchAndWriteReport { username = username, repos = repos }
        |> BackendTask.andThen
            (\() ->
                BackendTask.File.rawFile "report.md"
                    |> BackendTask.allowFatal
            )
        |> BackendTask.andThen
            (\content ->
                let
                    lineCount : Int
                    lineCount =
                        List.length (String.lines content)
                in
                Script.log ("Report complete: " ++ String.fromInt lineCount ++ " lines written to report.md")
            )


{-| A full Script with CLI options that fetches stars, writes a report, reads it back,
and logs a summary. Exercises fromScript + virtual FS + HTTP simulation end-to-end.
-}
reportScript : Script.Script
reportScript =
    Script.withCliOptions
        (Program.config
            |> Program.add
                (OptionsParser.build
                    (\username repos -> { username = username, repos = repos })
                    |> OptionsParser.with
                        (Option.optionalKeywordArg "username"
                            |> Option.withDefault "dillonkearns"
                        )
                    |> OptionsParser.with
                        (Option.keywordArgList "repo")
                )
        )
        (\{ username, repos } ->
            let
                repoList : List String
                repoList =
                    if List.isEmpty repos then
                        [ "elm-pages" ]

                    else
                        repos
            in
            fetchWriteAndVerify { username = username, repos = repoList }
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
