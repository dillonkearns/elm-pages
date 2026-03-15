module TestTaskManager exposing (run)

import BackendTask
import Cli.Option as Option
import Cli.Option.Typed as TypedOption
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Pages.Script as Script exposing (Script)
import TsJson.Encode as TsEncode


{-| Simulates a Things 3-style task management CLI with subcommands,
typed options, keyword lists, optional args, and structured JSON output.
This is a no-op script used for testing LLM schema comprehension.
-}


type CliAction
    = Add AddFlags
    | Search SearchFlags
    | List_ ListFlags


type alias AddFlags =
    { title : String
    , notes : Maybe String
    , when_ : Maybe String
    , deadline : Maybe String
    , tags : List String
    , project : Maybe String
    }


type alias SearchFlags =
    { query : String
    , completed : Bool
    , tag : Maybe String
    , limit : Int
    }


type alias ListFlags =
    { project : Maybe String
    , tag : Maybe String
    , today : Bool
    }


config =
    { description = "Manage tasks: add, search, or list todos (Things 3-style)"
    , cliOptions =
        Program.config
            |> Program.add
                (OptionsParser.buildSubCommand "add" AddFlags
                    |> OptionsParser.withDescription "Create a new task with optional scheduling, tags, and project assignment"
                    |> OptionsParser.with
                        (TypedOption.requiredKeywordArg "title" TypedOption.string
                            |> TypedOption.withDescription "The task title"
                        )
                    |> OptionsParser.with
                        (TypedOption.optionalKeywordArg "notes" TypedOption.string
                            |> TypedOption.withDescription "Additional notes or description for the task"
                        )
                    |> OptionsParser.with
                        (TypedOption.optionalKeywordArg "when" TypedOption.string
                            |> TypedOption.withDescription "Schedule: today, evening, tomorrow, someday, or a date (YYYY-MM-DD)"
                        )
                    |> OptionsParser.with
                        (TypedOption.optionalKeywordArg "deadline" TypedOption.string
                            |> TypedOption.withDescription "Due date in YYYY-MM-DD format"
                        )
                    |> OptionsParser.with
                        (Option.keywordArgList "tags"
                            |> Option.withDescription "Tags to assign (can be repeated: --tags work --tags urgent)"
                        )
                    |> OptionsParser.with
                        (TypedOption.optionalKeywordArg "project" TypedOption.string
                            |> TypedOption.withDescription "Project to assign the task to"
                        )
                    |> OptionsParser.map Add
                )
            |> Program.add
                (OptionsParser.buildSubCommand "search" SearchFlags
                    |> OptionsParser.withDescription "Search tasks by text query with optional filters"
                    |> OptionsParser.with
                        (TypedOption.requiredKeywordArg "query" TypedOption.string
                            |> TypedOption.withDescription "Search text to match against task titles and notes"
                        )
                    |> OptionsParser.with
                        (TypedOption.flag "completed"
                            |> TypedOption.withDescription "Include completed tasks in results"
                        )
                    |> OptionsParser.with
                        (TypedOption.optionalKeywordArg "tag" TypedOption.string
                            |> TypedOption.withDescription "Filter results to tasks with this tag"
                        )
                    |> OptionsParser.with
                        (TypedOption.requiredKeywordArg "limit" TypedOption.int
                            |> TypedOption.withDescription "Maximum number of results to return"
                        )
                    |> OptionsParser.map Search
                )
            |> Program.add
                (OptionsParser.buildSubCommand "list" ListFlags
                    |> OptionsParser.withDescription "List tasks, optionally filtered by project, tag, or today view"
                    |> OptionsParser.with
                        (TypedOption.optionalKeywordArg "project" TypedOption.string
                            |> TypedOption.withDescription "Filter to tasks in this project"
                        )
                    |> OptionsParser.with
                        (TypedOption.optionalKeywordArg "tag" TypedOption.string
                            |> TypedOption.withDescription "Filter to tasks with this tag"
                        )
                    |> OptionsParser.with
                        (TypedOption.flag "today"
                            |> TypedOption.withDescription "Show only tasks scheduled for today"
                        )
                    |> OptionsParser.map List_
                )
    , encoder =
        TsEncode.object
            [ TsEncode.required "action" .action TsEncode.string
            , TsEncode.required "tasks"
                .tasks
                (TsEncode.list taskEncoder)
            , TsEncode.required "count" .count TsEncode.int
            ]
    , run =
        \action ->
            BackendTask.succeed (fakeResponse action)
    }


taskEncoder =
    TsEncode.object
        [ TsEncode.required "id" .id TsEncode.string
        , TsEncode.required "title" .title TsEncode.string
        , TsEncode.required "status" .status TsEncode.string
        , TsEncode.required "tags" .tags (TsEncode.list TsEncode.string)
        , TsEncode.optional "project" .project TsEncode.string
        , TsEncode.optional "when" .when_ TsEncode.string
        , TsEncode.optional "deadline" .deadline TsEncode.string
        , TsEncode.optional "notes" .notes TsEncode.string
        ]


fakeResponse action =
    case action of
        Add flags ->
            { action = "added"
            , tasks =
                [ { id = "FAKE-UUID-001"
                  , title = flags.title
                  , status = "open"
                  , tags = flags.tags
                  , project = flags.project
                  , when_ = flags.when_
                  , deadline = flags.deadline
                  , notes = flags.notes
                  }
                ]
            , count = 1
            }

        Search flags ->
            { action = "search"
            , tasks =
                List.range 1 (min flags.limit 3)
                    |> List.map
                        (\i ->
                            { id = "FAKE-UUID-" ++ String.fromInt i
                            , title = "Result " ++ String.fromInt i ++ " for: " ++ flags.query
                            , status =
                                if flags.completed then
                                    "completed"

                                else
                                    "open"
                            , tags =
                                case flags.tag of
                                    Just t ->
                                        [ t ]

                                    Nothing ->
                                        []
                            , project = Nothing
                            , when_ = Nothing
                            , deadline = Nothing
                            , notes = Nothing
                            }
                        )
            , count = min flags.limit 3
            }

        List_ flags ->
            { action = "list"
            , tasks =
                [ { id = "FAKE-UUID-010"
                  , title = "Sample task"
                  , status = "open"
                  , tags =
                        case flags.tag of
                            Just t ->
                                [ t ]

                            Nothing ->
                                []
                  , project = flags.project
                  , when_ =
                        if flags.today then
                            Just "today"

                        else
                            Nothing
                  , deadline = Nothing
                  , notes = Nothing
                  }
                ]
            , count = 1
            }


run : Script
run =
    Script.withSchema config
