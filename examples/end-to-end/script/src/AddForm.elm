module AddForm exposing (run)

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
import Gen.Basics
import Gen.Debug
import Gen.Effect
import Gen.Form
import Gen.Form.Field
import Gen.Form.FieldView
import Gen.Form.Validation
import Gen.Html.Styled as Html
import Gen.Html.Styled.Attributes
import Gen.List
import Gen.Pages.Script
import Gen.Platform.Sub
import Gen.Server.Request
import Gen.Server.Response
import Gen.View
import List.Extra
import Pages.Route exposing (Type(..))
import Pages.Script as Script exposing (Script)


type alias CliOptions =
    { moduleName : String
    , rest : List String
    }


run : Script
run =
    Script.withCliOptions program
        (\cliOptions ->
            let
                file : Elm.File
                file =
                    createFile (cliOptions.moduleName |> String.split ".") (List.map parseFields cliOptions.rest)
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
                |> OptionsParser.withRestArgs
                    (Option.restArgs "fields")
            )


moduleNameRegex : String
moduleNameRegex =
    "^[A-Z][a-zA-Z0-9_]*(\\.([A-Z][a-zA-Z0-9_]*))*$"


type Kind
    = FieldInt
    | FieldString
    | FieldText
    | FieldFloat
    | FieldTime
    | FieldDate
    | FieldBool


formWithFields :
    List ( String, Kind )
    -> { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression }
formWithFields fields =
    Elm.Declare.function "form"
        []
        (\_ ->
            fields
                |> List.foldl
                    (\( fieldName, kind ) chain ->
                        chain
                            |> Gen.Form.field fieldName
                                (case kind of
                                    FieldString ->
                                        Gen.Form.Field.text
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldInt ->
                                        Gen.Form.Field.int { invalid = \_ -> Elm.string "" }
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldText ->
                                        Gen.Form.Field.text
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldFloat ->
                                        Gen.Form.Field.float { invalid = \_ -> Elm.string "" }
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldTime ->
                                        Gen.Form.Field.time { invalid = \_ -> Elm.string "" }
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldDate ->
                                        Gen.Form.Field.date { invalid = \_ -> Elm.string "" }
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldBool ->
                                        Gen.Form.Field.checkbox
                                )
                    )
                    (Gen.Form.init
                        (Elm.function (List.map fieldToParam fields)
                            (\params ->
                                Elm.record
                                    [ ( "combine"
                                      , params
                                            |> List.foldl
                                                (\fieldExpression chain ->
                                                    chain
                                                        |> Gen.Form.Validation.andMap fieldExpression
                                                )
                                                (Gen.Form.Validation.succeed (Elm.val "ParsedForm"))
                                      )
                                    , ( "view"
                                      , Elm.fn ( "formState", Nothing )
                                            (\formState ->
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
                                                                ++ [ Html.button []
                                                                        [ Html.text "Submit"
                                                                        ]
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
                                                                    , field |> Gen.Form.FieldView.inputStyled []
                                                                    , errorsView.call (Elm.get "errors" formState) field
                                                                    ]
                                                                ]
                                                        )
                                                    |> Elm.Let.toExpression
                                            )
                                      )
                                    ]
                            )
                        )
                    )
                |> Elm.withType
                    (Elm.Annotation.namedWith [ "Form" ]
                        "DoneForm"
                        [ Elm.Annotation.string
                        , Elm.Annotation.named [] "ParsedForm"
                        , Elm.Annotation.unit
                        , Elm.Annotation.list
                            (Elm.Annotation.namedWith [ "Html", "Styled" ]
                                "Html"
                                [ Elm.Annotation.namedWith
                                    [ "Pages", "Msg" ]
                                    "Msg"
                                    [ Elm.Annotation.named [] "Msg" ]
                                ]
                            )
                        ]
                    )
        )


errorsView :
    { declaration : Elm.Declaration
    , call : Elm.Expression -> Elm.Expression -> Elm.Expression
    , callFrom : List String -> Elm.Expression -> Elm.Expression -> Elm.Expression
    }
errorsView =
    Elm.Declare.fn2 "errorsView"
        --errorsView : Form.Errors String -> Validation.Field String parsed kind -> Html.Styled.Html (PagesMsg Msg)
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
                                        [ Gen.Html.Styled.Attributes.style "color" "red"
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
                    (Elm.Annotation.namedWith [ "Html", "Styled" ]
                        "Html"
                        [ Elm.Annotation.namedWith
                            [ "Pages", "Msg" ]
                            "Msg"
                            [ Elm.Annotation.named [] "Msg" ]
                        ]
                    )
        )


fieldToParam : ( String, Kind ) -> ( String, Maybe Elm.Annotation.Annotation )
fieldToParam ( name, kind ) =
    ( name, Nothing )


parseFields : String -> ( String, Kind )
parseFields rawField =
    case String.split ":" rawField of
        [ fieldName ] ->
            ( fieldName, FieldString )

        [ fieldName, fieldKind ] ->
            ( fieldName
            , case fieldKind of
                "string" ->
                    FieldString

                "text" ->
                    FieldText

                "bool" ->
                    FieldBool

                "time" ->
                    FieldTime

                "date" ->
                    FieldDate

                _ ->
                    FieldString
            )

        _ ->
            ( "ERROR", FieldString )


createFile : List String -> List ( String, Kind ) -> Elm.File
createFile moduleName fields =
    let
        form : { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression }
        form =
            formWithFields fields
    in
    Pages.Route.serverRender
        { moduleName = moduleName
        , action =
            ( Alias
                (Elm.Annotation.record
                    [ ( "errors", Elm.Annotation.namedWith [ "Form" ] "Response" [ Elm.Annotation.string ] )
                    ]
                )
            , \routeParams ->
                Gen.Server.Request.formData (Gen.Form.initCombined Gen.Basics.call_.identity (form.call []))
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
        |> Pages.Route.addDeclarations
            [ formWithFields fields |> .declaration
            , Elm.alias "ParsedForm"
                (fields
                    |> List.map
                        (\( fieldName, kind ) ->
                            ( fieldName
                            , case kind of
                                FieldString ->
                                    Elm.Annotation.string

                                FieldInt ->
                                    Elm.Annotation.int

                                FieldText ->
                                    Elm.Annotation.string

                                FieldFloat ->
                                    Elm.Annotation.float

                                FieldTime ->
                                    Elm.Annotation.named [ "Form", "Field" ] "TimeOfDay"

                                FieldDate ->
                                    Elm.Annotation.named [ "Date" ] "Date"

                                FieldBool ->
                                    Elm.Annotation.bool
                            )
                        )
                    |> Elm.Annotation.record
                )
            , errorsView.declaration
            ]
        |> Pages.Route.buildWithLocalState
            { view =
                \{ maybeUrl, sharedModel, model, app } ->
                    Gen.View.make_.view
                        { title = moduleName |> String.join "." |> Elm.string
                        , body =
                            Elm.list
                                [ Html.h2 [] [ Html.text "Form" ]
                                , form.call []
                                    |> Gen.Form.toDynamicTransition "form"
                                    |> Gen.Form.renderStyledHtml [] (Elm.get "errors" >> Elm.just) app Elm.unit
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


effectType : Elm.Annotation.Annotation
effectType =
    Elm.Annotation.namedWith [ "Effect" ] "Effect" [ Elm.Annotation.var "msg" ]
