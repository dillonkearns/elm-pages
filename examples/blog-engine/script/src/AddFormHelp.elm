module AddFormHelp exposing (Kind(..), parseField, provide, restArgsParser)

{-| -}

import Cli.Option
import Elm
import Elm.Annotation
import Elm.Declare
import Elm.Let
import Elm.Op
import Gen.Form
import Gen.Form.Field
import Gen.Form.FieldView
import Gen.Form.Validation
import Gen.Html as Html
import Gen.Html.Attributes
import Gen.List
import List.Extra
import Result.Extra


{-| -}
type Kind
    = FieldInt
    | FieldString
    | FieldText
    | FieldFloat
    | FieldTime
    | FieldDate
    | FieldBool


{-| -}
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
                                            )
                                      )
                                    ]
                            )
                        )
                    )
                |> Elm.withType
                    (Elm.Annotation.namedWith [ "Form" ]
                        "HtmlForm"
                        [ Elm.Annotation.string
                        , Elm.Annotation.named [] "ParsedForm"
                        , Elm.Annotation.var "input"
                        , Elm.Annotation.named [] "Msg"
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


fieldToParam : ( String, Kind ) -> ( String, Maybe Elm.Annotation.Annotation )
fieldToParam ( name, kind ) =
    ( name, Nothing )


restArgsParser : Cli.Option.Option (List String) (List ( String, Kind )) Cli.Option.RestArgsOption
restArgsParser =
    Cli.Option.restArgs "formFields"
        |> Cli.Option.validateMap
            (\items ->
                items
                    |> List.map parseField
                    |> Result.Extra.combine
            )


{-| -}
parseField : String -> Result String ( String, Kind )
parseField rawField =
    case String.split ":" rawField of
        [ fieldName ] ->
            Ok ( fieldName, FieldString )

        [ fieldName, fieldKind ] ->
            (case fieldKind of
                "string" ->
                    Ok FieldString

                "text" ->
                    Ok FieldText

                "bool" ->
                    Ok FieldBool

                "time" ->
                    Ok FieldTime

                "date" ->
                    Ok FieldDate

                invalidFieldKind ->
                    Err ("I wasn't able to interpret the type of the field `" ++ fieldName ++ "` because it has an unexpected field type `" ++ invalidFieldKind ++ "`.")
            )
                |> Result.map (Tuple.pair fieldName)

        _ ->
            Err ("Unexpected form field format: `" ++ rawField ++ "`. Must be in format `first` or `checkin:date`.")


{-| -}
provide :
    List ( String, Kind )
    ->
        { formHandlers : { declaration : Elm.Declaration, value : Elm.Expression }
        , renderForm : Elm.Expression -> Elm.Expression
        , declarations : List Elm.Declaration
        }
provide fields =
    let
        form : { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression }
        form =
            formWithFields fields
    in
    { formHandlers =
        { declaration =
            Elm.declaration "formHandlers"
                (Gen.Form.call_.initCombined (Elm.val "Action") (form.call [])
                    |> Elm.withType
                        (Elm.Annotation.namedWith [ "Form" ]
                            "ServerForms"
                            [ Elm.Annotation.string
                            , Elm.Annotation.named [] "Action"
                            ]
                        )
                )
        , value = Elm.val "formHandlers"
        }
    , renderForm =
        \app ->
            form.call []
                |> Gen.Form.toDynamicTransition "form"
                |> Gen.Form.renderHtml [] (Elm.get "errors" >> Elm.just) app Elm.unit
    , declarations =
        [ formWithFields fields |> .declaration
        , Elm.customType "Action"
            [ Elm.variantWith "Action" [ Elm.Annotation.named [] "ParsedForm" ]
            ]

        -- TODO customize formHandlers name?
        , Elm.declaration "formHandlers" (Gen.Form.call_.initCombined (Elm.val "Action") (form.call []))

        -- TODO customize ParsedForm name?
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
    }
