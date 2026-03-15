module TestDbSchema exposing (run)

import BackendTask
import Cli.Option.Typed as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Pages.Script as Script exposing (Script)
import TsJson.Encode as TsEncode


type alias Flags =
    { tableName : String
    , limit : Int
    , verbose : Bool
    }


config =
    { description = "Query a database table and return rows with metadata"
    , cliOptions =
        Program.config
            |> Program.add
                (OptionsParser.build Flags
                    |> OptionsParser.with
                        (Option.requiredKeywordArg "table" Option.string
                            |> Option.withDescription "The database table to query"
                        )
                    |> OptionsParser.with
                        (Option.requiredKeywordArg "limit" Option.int
                            |> Option.withDescription "Maximum number of rows to return"
                        )
                    |> OptionsParser.with
                        (Option.flag "verbose"
                            |> Option.withDescription "Include column type metadata in the output"
                        )
                )
    , encoder =
        TsEncode.object
            [ TsEncode.required "table" .table TsEncode.string
            , TsEncode.required "rowCount" .rowCount TsEncode.int
            , TsEncode.required "rows"
                .rows
                (TsEncode.list
                    (TsEncode.object
                        [ TsEncode.required "id" .id TsEncode.int
                        , TsEncode.required "name" .name TsEncode.string
                        ]
                    )
                )
            ]
    , run =
        \flags ->
            BackendTask.succeed
                { table = flags.tableName
                , rowCount = flags.limit
                , rows =
                    List.range 1 flags.limit
                        |> List.map
                            (\i ->
                                { id = i
                                , name = "row-" ++ String.fromInt i
                                }
                            )
                }
    }


run : Script
run =
    Script.withSchema config
