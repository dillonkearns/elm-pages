module AddRoute exposing (run)

import AddFormHelp
import BackendTask
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Elm
import Elm.Annotation as Type
import Elm.Case
import Elm.Declare
import Elm.Let
import Elm.Op
import Gen.BackendTask
import Gen.Debug
import Gen.Effect as Effect
import Gen.Form as Form
import Gen.Form.FieldView as FieldView
import Gen.Html as Html
import Gen.Html.Attributes as Attr
import Gen.List
import Gen.Pages.Script
import Gen.Platform.Sub
import Gen.Server.Request as Request
import Gen.Server.Response as Response
import Gen.View
import List.Extra
import Pages.Generate exposing (Type(..))
import Pages.Script as Script exposing (Script)


type alias CliOptions =
    { moduleName : List String
    , rest : List ( String, AddFormHelp.Kind )
    }


run : Script
run =
    Script.withCliOptions program
        (\cliOptions ->
            let
                file : Elm.File
                file =
                    createFile cliOptions.moduleName cliOptions.rest
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
                |> OptionsParser.with (Option.requiredPositionalArg "module" |> Pages.Generate.moduleNameCliArg)
                |> OptionsParser.withRestArgs AddFormHelp.restArgsParser
            )


createFile : List String -> List ( String, AddFormHelp.Kind ) -> Elm.File
createFile moduleName fields =
    let
        formHelpers :
            Maybe
                { formHandlers : { declaration : Elm.Declaration, value : Elm.Expression }
                , form : Elm.Expression
                , declarations : List Elm.Declaration
                }
        formHelpers =
            AddFormHelp.provide
                { fields = fields
                , elmCssView = False
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
                                                    [ Attr.disabled True
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
                                ( "label", Type.string |> Just )
                                ( "field", Nothing )
                                (\label field ->
                                    Html.div []
                                        [ Html.label []
                                            [ Html.call_.text (Elm.Op.append label (Elm.string " "))
                                            , field |> FieldView.input []
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
                (Type.record
                    (case formHelpers of
                        Just _ ->
                            [ ( "errors", Type.namedWith [ "Form" ] "Response" [ Type.string ] )
                            ]

                        Nothing ->
                            []
                    )
                )
            , \routeParams ->
                formHelpers
                    |> Maybe.map
                        (\justFormHelp ->
                            Request.formData justFormHelp.formHandlers.value
                                |> Request.call_.map
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
                                                                    Response.render
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
                    |> Maybe.withDefault
                        (Request.succeed
                            (Gen.BackendTask.succeed
                                (Response.render
                                    (Elm.record [])
                                )
                            )
                        )
            )
        , data =
            ( Alias (Type.record [])
            , \routeParams ->
                Request.succeed
                    (Gen.BackendTask.succeed
                        (Response.render
                            (Elm.record [])
                        )
                    )
            )
        , head = \app -> Elm.list []
        }
        |> Pages.Generate.addDeclarations
            (formHelpers
                |> Maybe.map .declarations
                |> Maybe.map ((::) errorsView.declaration)
                |> Maybe.withDefault []
            )
        |> Pages.Generate.buildWithLocalState
            { view =
                \{ maybeUrl, sharedModel, model, app } ->
                    Gen.View.make_.view
                        { title = moduleName |> String.join "." |> Elm.string
                        , body =
                            Elm.list
                                (case formHelpers of
                                    Just justFormHelp ->
                                        [ Html.h2 [] [ Html.text "Form" ]
                                        , justFormHelp.form
                                            |> Form.toDynamicTransition "form"
                                            |> Form.renderHtml [] (Elm.get "errors" >> Elm.just) app Elm.unit
                                        ]

                                    Nothing ->
                                        [ Html.h2 [] [ Html.text "New Page" ]
                                        ]
                                )
                        }
            , update =
                \{ pageUrl, sharedModel, app, msg, model } ->
                    Elm.Case.custom msg
                        (Type.named [] "Msg")
                        [ Elm.Case.branch0 "NoOp"
                            (Elm.tuple model
                                (Effect.none
                                    |> Elm.withType effectType
                                )
                            )
                        ]
            , init =
                \{ pageUrl, sharedModel, app } ->
                    Elm.tuple (Elm.record [])
                        (Effect.none
                            |> Elm.withType effectType
                        )
            , subscriptions =
                \{ maybePageUrl, routeParams, path, sharedModel, model } ->
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
                            [ "Pages", "Msg" ]
                            "Msg"
                            [ Type.named [] "Msg" ]
                        ]
                    )
        )


effectType : Type.Annotation
effectType =
    Type.namedWith [ "Effect" ] "Effect" [ Type.var "msg" ]
