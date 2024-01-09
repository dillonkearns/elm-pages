module AddStaticRoute exposing (run)

import BackendTask
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Elm
import Elm.Annotation as Type
import Elm.Case
import Gen.BackendTask
import Gen.Effect as Effect
import Gen.Html as Html
import Gen.Platform.Sub
import Gen.View
import Pages.Script as Script exposing (Script)
import Scaffold.Route exposing (Type(..))


type alias CliOptions =
    { moduleName : List String
    }


run : Script
run =
    Script.withCliOptions program
        (\cliOptions ->
            cliOptions
                |> createFile
                |> Script.writeFile
                |> BackendTask.allowFatal
        )


program : Program.Config CliOptions
program =
    Program.config
        |> Program.add
            (OptionsParser.build CliOptions
                |> OptionsParser.with (Option.requiredPositionalArg "module" |> Scaffold.Route.moduleNameCliArg)
            )


createFile : CliOptions -> { path : String, body : String }
createFile { moduleName } =
    Scaffold.Route.preRender
        { moduleName = moduleName
        , pages =
            Gen.BackendTask.succeed
                (Elm.list [])
        , data =
            ( Alias (Type.record [])
            , \routeParams ->
                Gen.BackendTask.succeed (Elm.record [])
            )
        , head = \app -> Elm.list []
        }
        |> Scaffold.Route.buildWithLocalState
            { view =
                \{ shared, model, app } ->
                    Gen.View.make_.view
                        { title = moduleName |> String.join "." |> Elm.string
                        , body =
                            Elm.list
                                [ Html.h2 [] [ Html.text "New Page" ]
                                ]
                        }
            , update =
                \{ shared, app, msg, model } ->
                    Elm.Case.custom msg
                        (Type.named [] "Msg")
                        [ Elm.Case.branch0 "NoOp"
                            (Elm.tuple model
                                Effect.none
                            )
                        ]
            , init =
                \{ shared, app } ->
                    Elm.tuple (Elm.record []) Effect.none
            , subscriptions =
                \{ routeParams, path, shared, model } ->
                    Gen.Platform.Sub.none
            , model =
                Alias (Type.record [])
            , msg =
                Custom [ Elm.variant "NoOp" ]
            }
