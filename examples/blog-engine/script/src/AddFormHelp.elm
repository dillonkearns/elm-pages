module AddFormHelp exposing (Kind(..), parseField, provide, restArgsParser)

{-| -}

import Cli.Option
import Elm
import Elm.Annotation as Type
import Elm.Declare
import Gen.Form
import Gen.Form.Field
import Result.Extra


{-| -}
type Kind
    = FieldInt
    | FieldText
    | FieldTextarea
    | FieldFloat
    | FieldTime
    | FieldDate
    | FieldCheckbox


{-| -}
formWithFields :
    Bool
    -> List ( String, Kind )
    ->
        ({ formState : Elm.Expression
         , params : List Elm.Expression
         }
         -> Elm.Expression
        )
    -> { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression }
formWithFields elmCssView fields viewFn =
    Elm.Declare.function "form"
        []
        (\_ ->
            fields
                |> List.foldl
                    (\( fieldName, kind ) chain ->
                        chain
                            |> Gen.Form.field fieldName
                                (case kind of
                                    FieldText ->
                                        Gen.Form.Field.text
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldInt ->
                                        Gen.Form.Field.int { invalid = \_ -> Elm.string "" }
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldTextarea ->
                                        Gen.Form.Field.text
                                            |> Gen.Form.Field.required (Elm.string "Required")
                                            |> Gen.Form.Field.textarea
                                                { rows = Elm.nothing
                                                , cols = Elm.nothing
                                                }

                                    FieldFloat ->
                                        Gen.Form.Field.float { invalid = \_ -> Elm.string "" }
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldTime ->
                                        Gen.Form.Field.time { invalid = \_ -> Elm.string "" }
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldDate ->
                                        Gen.Form.Field.date { invalid = \_ -> Elm.string "" }
                                            |> Gen.Form.Field.required (Elm.string "Required")

                                    FieldCheckbox ->
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
                                                        |> validationAndMap fieldExpression
                                                )
                                                (validationSucceed (Elm.val "ParsedForm"))
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
                    (Type.namedWith [ "Form" ]
                        (if elmCssView then
                            "StyledHtmlForm"

                         else
                            "HtmlForm"
                        )
                        [ Type.string
                        , Type.named [] "ParsedForm"
                        , Type.var "input"
                        , Type.named [] "Msg"
                        ]
                    )
        )


fieldToParam : ( String, Kind ) -> ( String, Maybe Type.Annotation )
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
            Ok ( fieldName, FieldText )

        [ fieldName, fieldKind ] ->
            (case fieldKind of
                "text" ->
                    Ok FieldText

                "textarea" ->
                    Ok FieldTextarea

                "checkbox" ->
                    Ok FieldCheckbox

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
    , elmCssView : Bool
    , view :
        { formState : Elm.Expression
        , params : List Elm.Expression
        }
        -> Elm.Expression
    }
    ->
        Maybe
            { formHandlers : { declaration : Elm.Declaration, value : Elm.Expression }
            , form : Elm.Expression
            , declarations : List Elm.Declaration
            }
provide { fields, view, elmCssView } =
    let
        form : { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression }
        form =
            formWithFields elmCssView fields view
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
                                (Type.namedWith [ "Form" ]
                                    "ServerForms"
                                    [ Type.string
                                    , Type.named [] "Action"
                                    ]
                                )
                        )
                , value = Elm.val "formHandlers"
                }
            , form = form.call []
            , declarations =
                [ formWithFields elmCssView fields view |> .declaration
                , Elm.customType "Action"
                    [ Elm.variantWith "Action" [ Type.named [] "ParsedForm" ]
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
                                    FieldText ->
                                        Type.string

                                    FieldInt ->
                                        Type.int

                                    FieldTextarea ->
                                        Type.string

                                    FieldFloat ->
                                        Type.float

                                    FieldTime ->
                                        Type.named [ "Form", "Field" ] "TimeOfDay"

                                    FieldDate ->
                                        Type.named [ "Date" ] "Date"

                                    FieldCheckbox ->
                                        Type.bool
                                )
                            )
                        |> Type.record
                    )
                ]
            }


validationAndMap : Elm.Expression -> Elm.Expression -> Elm.Expression
validationAndMap andMapArg andMapArg0 =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Validation" ]
            , name = "andMap"
            , annotation =
                Just
                    (Type.function
                        [ Type.namedWith
                            []
                            "Validation"
                            [ Type.var "error"
                            , Type.var "a"
                            , Type.var "named1"
                            , Type.var "constraints1"
                            ]
                        , Type.namedWith
                            []
                            "Validation"
                            [ Type.var "error"
                            , Type.function [ Type.var "a" ] (Type.var "b")
                            , Type.var "named2"
                            , Type.var "constraints2"
                            ]
                        ]
                        (Type.namedWith
                            []
                            "Combined"
                            [ Type.var "error", Type.var "b" ]
                        )
                    )
            }
        )
        [ andMapArg, andMapArg0 ]


validationSucceed : Elm.Expression -> Elm.Expression
validationSucceed succeedArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Validation" ]
            , name = "succeed"
            , annotation =
                Just
                    (Type.function
                        [ Type.var "parsed" ]
                        (Type.namedWith
                            []
                            "Combined"
                            [ Type.var "error", Type.var "parsed" ]
                        )
                    )
            }
        )
        [ succeedArg ]
