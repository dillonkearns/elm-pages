module MyCli exposing (generator)

import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import DataSource exposing (DataSource)
import DataSource.Http
import DataSource.Port
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Generator exposing (Generator)


generator : Generator
generator =
    Pages.Generator.withCliOptions program
        (\{ username, repo } ->
            DataSource.Http.get
                ("https://api.github.com/repos/dillonkearns/" ++ repo)
                (Decode.field "stargazers_count" Decode.int)
                |> DataSource.andThen
                    (\stars ->
                        log
                            (String.fromInt stars)
                    )
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


log : String -> DataSource ()
log message =
    DataSource.Port.get "log"
        (Encode.string message)
        (Decode.succeed ())
