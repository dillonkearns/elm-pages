module AddRoute exposing (run)

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
                                ( "label", Type.string |> Just )
                                ( "field", Nothing )
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
                                    (Elm.fn ( "formData", Nothing )
                                        (\formData ->
                                            Elm.Case.tuple formData
                                                "response"
                                                "parsedForm"
                                                (\response parsedForm ->
                                                    Elm.Case.custom parsedForm
                                                        Type.int
                                                        [ Elm.Case.branch1 "Form.Valid"
                                                            ( "validatedForm", Type.int )
                                                            (\validatedForm ->
                                                                Elm.Case.custom validatedForm
                                                                    Type.int
                                                                    [ Elm.Case.branch1 "Action"
                                                                        ( "parsed", Type.int )
                                                                        (\parsed ->
                                                                            Scaffold.Form.recordEncoder parsed fields
                                                                                |> Gen.Json.Encode.encode 2
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
                                                                    ]
                                                            )
                                                        , Elm.Case.branch2 "Form.Invalid"
                                                            ( "parsed", Type.int )
                                                            ( "error", Type.int )
                                                            (\_ _ ->
                                                                "Form validations did not succeed!"
                                                                    |> Gen.Pages.Script.log
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
                                                        ]
                                                )
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
