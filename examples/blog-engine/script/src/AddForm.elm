module AddForm exposing (run)

import AddFormHelp
import BackendTask
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Cli.Validate
import Elm
import Elm.Annotation
import Elm.Case
import Elm.Declare
import Elm.Let
import Elm.Op
import Gen.BackendTask
import Gen.Debug
import Gen.Effect
import Gen.Form
import Gen.Form.FieldView
import Gen.Html as Html
import Gen.Html.Attributes
import Gen.List
import Gen.Pages.Script
import Gen.Platform.Sub
import Gen.Server.Request
import Gen.Server.Response
import Gen.View
import List.Extra
import Pages.Generate exposing (Type(..))
import Pages.Script as Script exposing (Script)


type alias CliOptions =
    { moduleName : String
    , rest : List ( String, AddFormHelp.Kind )
    }


run : Script
run =
    Script.withCliOptions program
        (\cliOptions ->
            let
                file : Elm.File
                file =
                    createFile (cliOptions.moduleName |> String.split ".") cliOptions.rest
            in
            Script.writeFile
                { path = "app/" ++ file.path
                , body = file.contents
                }
                |> BackendTask.allowFatal
        )


program : Program.Config CliOptions
program =
    Program.config
        |> Program.add
            (OptionsParser.build CliOptions
                |> OptionsParser.with
                    (Option.requiredPositionalArg "module"
                        |> Option.validate (Cli.Validate.regex moduleNameRegex)
                    )
                |> OptionsParser.withRestArgs AddFormHelp.restArgsParser
            )


moduleNameRegex : String
moduleNameRegex =
    "^[A-Z][a-zA-Z0-9_]*(\\.([A-Z][a-zA-Z0-9_]*))*$"


createFile : List String -> List ( String, AddFormHelp.Kind ) -> Elm.File
createFile moduleName fields =
    let
        formHelp :
            { formHandlers : { declaration : Elm.Declaration, value : Elm.Expression }
            , renderForm : Elm.Expression -> Elm.Expression
            , declarations : List Elm.Declaration
            }
        formHelp =
            AddFormHelp.provide
                { fields = fields
                , view =
                    \{ formState, params } ->
                        Elm.Let.letIn
                            (\fieldView ->
                                Elm.list
                                    ((params
                                        |> List.Extra.zip fields
                                        |> List.map
                                            (\( ( name, kind ), param ) ->
                                                fieldView (Elm.string name) param
                                            )
                                     )
                                        ++ [ Elm.ifThen (formState |> Elm.get "isTransitioning")
                                                (Html.button
                                                    [ Gen.Html.Attributes.disabled True
                                                    ]
                                                    [ Html.text "Submitting..."
                                                    ]
                                                )
                                                (Html.button []
                                                    [ Html.text "Submit"
                                                    ]
                                                )
                                           ]
                                    )
                            )
                            |> Elm.Let.fn2 "fieldView"
                                ( "label", Elm.Annotation.string |> Just )
                                ( "field", Nothing )
                                (\label field ->
                                    Html.div []
                                        [ Html.label []
                                            [ Html.call_.text (Elm.Op.append label (Elm.string " "))
                                            , field |> Gen.Form.FieldView.input []
                                            , errorsView.call (Elm.get "errors" formState) field
                                            ]
                                        ]
                                )
                            |> Elm.Let.toExpression
                }
    in
    Pages.Generate.serverRender
        { moduleName = moduleName
        , action =
            ( Alias
                (Elm.Annotation.record
                    [ ( "errors", Elm.Annotation.namedWith [ "Form" ] "Response" [ Elm.Annotation.string ] )
                    ]
                )
            , \routeParams ->
                Gen.Server.Request.formData formHelp.formHandlers.value
                    |> Gen.Server.Request.call_.map
                        (Elm.fn ( "formData", Nothing )
                            (\formData ->
                                Elm.Case.tuple formData
                                    "response"
                                    "parsedForm"
                                    (\response parsedForm ->
                                        Gen.Debug.toString parsedForm
                                            |> Gen.Pages.Script.call_.log
                                            |> Gen.BackendTask.call_.map
                                                (Elm.fn ( "_", Nothing )
                                                    (\_ ->
                                                        Gen.Server.Response.render
                                                            (Elm.record
                                                                [ ( "errors", response )
                                                                ]
                                                            )
                                                    )
                                                )
                                    )
                            )
                        )
            )
        , data =
            ( Alias (Elm.Annotation.record [])
            , \routeParams ->
                Gen.Server.Request.succeed
                    (Gen.BackendTask.succeed
                        (Gen.Server.Response.render
                            (Elm.record [])
                        )
                    )
            )
        , head = \app -> Elm.list []
        }
        |> Pages.Generate.addDeclarations formHelp.declarations
        |> Pages.Generate.addDeclarations
            [ errorsView.declaration
            ]
        |> Pages.Generate.buildWithLocalState
            { view =
                \{ maybeUrl, sharedModel, model, app } ->
                    Gen.View.make_.view
                        { title = moduleName |> String.join "." |> Elm.string
                        , body =
                            Elm.list
                                [ Html.h2 [] [ Html.text "Form" ]
                                , formHelp.renderForm app -- TODO customize argument with `(Elm.get "errors" >> Elm.just)` and `Elm.unit`?
                                ]
                        }
            , update =
                \{ pageUrl, sharedModel, app, msg, model } ->
                    Elm.Case.custom msg
                        (Elm.Annotation.named [] "Msg")
                        [ Elm.Case.branch0 "NoOp"
                            (Elm.tuple model
                                (Gen.Effect.none
                                    |> Elm.withType effectType
                                )
                            )
                        ]
            , init =
                \{ pageUrl, sharedModel, app } ->
                    Elm.tuple (Elm.record [])
                        (Gen.Effect.none
                            |> Elm.withType effectType
                        )
            , subscriptions =
                \{ maybePageUrl, routeParams, path, sharedModel, model } ->
                    Gen.Platform.Sub.none
            , model =
                Alias (Elm.Annotation.record [])
            , msg =
                Custom [ Elm.variant "NoOp" ]
            }


errorsView :
    { declaration : Elm.Declaration
    , call : Elm.Expression -> Elm.Expression -> Elm.Expression
    , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression
    }
errorsView =
    Elm.Declare.fn2 "errorsView"
        ( "errors", Elm.Annotation.namedWith [ "Form" ] "Errors" [ Elm.Annotation.string ] |> Just )
        ( "field"
        , Elm.Annotation.namedWith [ "Form", "Validation" ]
            "Field"
            [ Elm.Annotation.string
            , Elm.Annotation.var "parsed"
            , Elm.Annotation.var "kind"
            ]
            |> Just
        )
        (\errors field ->
            Elm.ifThen
                (Gen.List.call_.isEmpty (Gen.Form.errorsForField field errors))
                (Html.div [] [])
                (Html.div
                    []
                    [ Html.call_.ul (Elm.list [])
                        (Gen.List.call_.map
                            (Elm.fn ( "error", Nothing )
                                (\error ->
                                    Html.li
                                        [ Gen.Html.Attributes.style "color" "red"
                                        ]
                                        [ Html.call_.text error
                                        ]
                                )
                            )
                            (Gen.Form.errorsForField field errors)
                        )
                    ]
                )
                |> Elm.withType
                    (Elm.Annotation.namedWith [ "Html" ]
                        "Html"
                        [ Elm.Annotation.namedWith
                            [ "Pages", "Msg" ]
                            "Msg"
                            [ Elm.Annotation.named [] "Msg" ]
                        ]
                    )
        )


effectType : Elm.Annotation.Annotation
effectType =
    Elm.Annotation.namedWith [ "Effect" ] "Effect" [ Elm.Annotation.var "msg" ]
