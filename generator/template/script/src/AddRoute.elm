module AddRoute exposing (run)

import BackendTask
import Cli.Option as Option
import Cli.OptionsParser as OptionsParser
import Cli.Program as Program
import Elm
import Elm.Annotation as Type
import Elm.Arg
import Elm.Case
import Elm.Declare exposing (Function, fn2)
import Elm.Let
import Elm.Op
import Gen.BackendTask
import Gen.Effect as Effect
import Gen.FatalError
import Gen.Form as Form
import Gen.Form.FieldView as FieldView
import Gen.Html as Html
import Gen.Html.Attributes as Attr
import Gen.Json.Encode
import Gen.List
import Gen.Maybe
import Gen.Pages.Form as PagesForm
import Gen.Pages.Script
import Gen.Platform.Sub
import Gen.Server.Request as Request
import Gen.Server.Response as Response
import Gen.View
import Pages.Script as Script exposing (Script)
import Scaffold.Form
import Scaffold.Route exposing (Type(..))


type alias CliOptions =
    { moduleName : List String
    , fields : List ( String, Scaffold.Form.Kind )
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
                |> OptionsParser.withRestArgs Scaffold.Form.restArgsParser
            )


createFile : CliOptions -> { path : String, body : String }
createFile { moduleName, fields } =
    let
        formHelpers :
            Maybe
                { formHandlers : Elm.Expression
                , form : Elm.Expression
                , declarations : List Elm.Declaration
                }
        formHelpers =
            Scaffold.Form.provide
                { fields = fields
                , elmCssView = False
                , view =
                    \{ formState, params } ->
                        Elm.Let.letIn
                            (\fieldView ->
                                Elm.list
                                    ((params
                                        |> List.map
                                            (\{ name, kind, param } ->
                                                fieldView (Elm.string name) param
                                            )
                                     )
                                        ++ [ Elm.ifThen formState.submitting
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
                                (Elm.Arg.var "label")
                                (Elm.Arg.var "field")
                                (\label field ->
                                    Html.div []
                                        [ Html.label []
                                            [ Html.call_.text (Elm.Op.append label (Elm.string " "))
                                            , field |> FieldView.input []
                                            , errorsView.call formState.errors field
                                            ]
                                        ]
                                )
                            |> Elm.Let.toExpression
                }
    in
    Scaffold.Route.serverRender
        { moduleName = moduleName
        , action =
            ( Alias
                (Type.record
                    (case formHelpers of
                        Just _ ->
                            [ ( "errors", Type.namedWith [ "Form" ] "ServerResponse" [ Type.string ] )
                            ]

                        Nothing ->
                            []
                    )
                )
            , \routeParams request ->
                formHelpers
                    |> Maybe.map
                        (\justFormHelp ->
                            Request.formData justFormHelp.formHandlers request
                                |> Gen.Maybe.call_.map
                                    (Elm.fn (Elm.Arg.var "formData")
                                        (\formData ->
                                            Elm.Case.custom
                                                formData
                                                Type.unit
                                                [ Elm.Case.branch
                                                    (Elm.Arg.tuple
                                                        (Elm.Arg.var "response")
                                                        (Elm.Arg.var "parsedForm")
                                                    )
                                                    (\( response, parsedForm ) ->
                                                        Elm.Case.custom parsedForm
                                                            Type.int
                                                            [ Elm.Case.branch
                                                                (Elm.Arg.customType "Form.Valid" identity
                                                                    |> Elm.Arg.item (Elm.Arg.var "validatedForm")
                                                                )
                                                                (\validatedForm ->
                                                                    Elm.Case.custom validatedForm
                                                                        Type.int
                                                                        [ Elm.Case.branch
                                                                            (Elm.Arg.customType "Action" identity
                                                                                |> Elm.Arg.item (Elm.Arg.var "parsed")
                                                                            )
                                                                            (\parsed ->
                                                                                Scaffold.Form.recordEncoder parsed fields
                                                                                    |> Gen.Json.Encode.encode 2
                                                                                    |> Gen.Pages.Script.call_.log
                                                                                    |> Gen.BackendTask.call_.map
                                                                                        (Elm.fn Elm.Arg.ignore
                                                                                            (\_ ->
                                                                                                Response.render
                                                                                                    (Elm.record
                                                                                                        [ ( "errors", response )
                                                                                                        ]
                                                                                                    )
                                                                                            )
                                                                                        )
                                                                            )
                                                                        ]
                                                                )
                                                            , Elm.Case.branch
                                                                (Elm.Arg.customType
                                                                    "Form.Invalid"
                                                                    Tuple.pair
                                                                    |> Elm.Arg.item (Elm.Arg.var "parsed")
                                                                    |> Elm.Arg.item (Elm.Arg.var "error")
                                                                )
                                                                (\( _, _ ) ->
                                                                    "Form validations did not succeed!"
                                                                        |> Gen.Pages.Script.log
                                                                        |> Gen.BackendTask.call_.map
                                                                            (Elm.fn Elm.Arg.ignore
                                                                                (\_ ->
                                                                                    Response.render
                                                                                        (Elm.record
                                                                                            [ ( "errors", response )
                                                                                            ]
                                                                                        )
                                                                                )
                                                                            )
                                                                )
                                                            ]
                                                    )
                                                ]
                                        )
                                    )
                                |> Gen.Maybe.withDefault
                                    (Gen.BackendTask.fail
                                        (Gen.FatalError.fromString "Expected form post")
                                    )
                        )
                    |> Maybe.withDefault
                        (Gen.BackendTask.succeed
                            (Response.render
                                (Elm.record [])
                            )
                        )
            )
        , data =
            ( Alias (Type.record [])
            , \routeParams request ->
                Gen.BackendTask.succeed
                    (Response.render
                        (Elm.record [])
                    )
            )
        , head = \app -> Elm.list []
        }
        |> Scaffold.Route.addDeclarations
            (formHelpers
                |> Maybe.map .declarations
                |> Maybe.map ((::) errorsView.declaration)
                |> Maybe.withDefault []
            )
        |> Scaffold.Route.buildWithLocalState
            { view =
                \{ shared, model, app } ->
                    Gen.View.make_.view
                        { title = moduleName |> String.join "." |> Elm.string
                        , body =
                            Elm.list
                                (case formHelpers of
                                    Just justFormHelp ->
                                        [ Html.h2 [] [ Html.text "Form" ]
                                        , justFormHelp.form
                                            |> PagesForm.call_.renderHtml
                                                (Elm.list [])
                                                (Form.options "form"
                                                    |> Form.withServerResponse
                                                        (app
                                                            |> Elm.get "action"
                                                            |> Gen.Maybe.map (Elm.get "errors")
                                                        )
                                                )
                                                app
                                        ]

                                    Nothing ->
                                        [ Html.h2 [] [ Html.text "New Page" ]
                                        ]
                                )
                        }
            , update =
                \{ shared, app, msg, model } ->
                    Elm.Case.custom msg
                        (Type.named [] "Msg")
                        [ Elm.Case.branch (Elm.Arg.customType "NoOp" ())
                            (\() ->
                                Elm.tuple model
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


errorsView : Function (Elm.Expression -> Elm.Expression -> Elm.Expression)
errorsView =
    fn2 "errorsView"
        (Elm.Arg.var "errors")
        (Elm.Arg.var "field")
        (\errors field ->
            Elm.ifThen
                (Gen.List.call_.isEmpty (Form.errorsForField field errors))
                (Html.div [] [])
                (Html.div
                    []
                    [ Html.call_.ul (Elm.list [])
                        (Gen.List.call_.map
                            (Elm.fn (Elm.Arg.var "error")
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
