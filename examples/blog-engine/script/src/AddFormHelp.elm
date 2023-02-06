module AddFormHelp exposing (Kind(..), parseField, provide, restArgsParser)

{-| -}

import Cli.Option
import Elm
import Elm.Annotation
import Elm.Declare
import Gen.Form
import Gen.Form.Field
import Gen.Form.Validation
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
    ->
        ({ formState : Elm.Expression
         , params : List Elm.Expression
         }
         -> Elm.Expression
        )
    -> { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression }
formWithFields fields viewFn =
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
                                                viewFn { formState = formState, params = params }
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
    { fields : List ( String, Kind )
    , view :
        { formState : Elm.Expression
        , params : List Elm.Expression
        }
        -> Elm.Expression
    }
    ->
        Maybe
            { formHandlers : { declaration : Elm.Declaration, value : Elm.Expression }
            , renderForm : Elm.Expression -> Elm.Expression
            , declarations : List Elm.Declaration
            }
provide { fields, view } =
    let
        form : { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression }
        form =
            formWithFields fields view
    in
    if List.isEmpty fields then
        Nothing

    else
        Just
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
                [ formWithFields fields view |> .declaration
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
                ]
            }
