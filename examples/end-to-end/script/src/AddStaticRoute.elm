module AddStaticRoute exposing (run)

import BackendTask
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Elm
import Elm.Annotation as Type
import Elm.Case
import Elm.Declare
import Gen.BackendTask
import Gen.Effect as Effect
import Gen.Form as Form
import Gen.Html as Html
import Gen.Html.Attributes as Attr
import Gen.List
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
        , pages = Gen.BackendTask.succeed (Elm.list [])
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


errorsView :
    { declaration : Elm.Declaration
    , call : Elm.Expression -> Elm.Expression -> Elm.Expression
    , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression
    , value : List String -> Elm.Expression
    }
errorsView =
    Elm.Declare.fn2 "errorsView"
        ( "errors", Type.namedWith [ "Form" ] "Errors" [ Type.string ] |> Just )
        ( "field"
        , Type.namedWith [ "Form", "Validation" ]
            "Field"
            [ Type.string
            , Type.var "parsed"
            , Type.var "kind"
            ]
            |> Just
        )
        (\errors field ->
            Elm.ifThen
                (Gen.List.call_.isEmpty (Form.errorsForField field errors))
                (Html.div [] [])
                (Html.div
                    []
                    [ Html.call_.ul (Elm.list [])
                        (Gen.List.call_.map
                            (Elm.fn ( "error", Nothing )
                                (\error ->
                                    Html.li
                                        [ Attr.style "color" "red"
                                        ]
                                        [ Html.call_.text error
                                        ]
                                )
                            )
                            (Form.errorsForField field errors)
                        )
                    ]
                )
                |> Elm.withType
                    (Type.namedWith [ "Html" ]
                        "Html"
                        [ Type.namedWith
                            [ "PagesMsg" ]
                            "PagesMsg"
                            [ Type.named [] "Msg" ]
                        ]
                    )
        )
