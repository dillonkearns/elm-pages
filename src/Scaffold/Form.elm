module Scaffold.Form exposing
    ( Kind(..), provide, restArgsParser
    , Context
    , recordEncoder, fieldEncoder
    )

{-| This module helps you with scaffolding a form in `elm-pages`, similar to how rails generators are used to scaffold out forms to
get up and running quickly with the starting point for a form with different field types. See also [`Scaffold.Route`](Scaffold-Route).

See the `AddRoute` script in the starter template for an example. It's usually easiest to modify that script as a starting
point rather than using this API from scratch.

Using the `AddRoute` script from the default starter template, you can run a command like this:

`npx elm-pages run AddRoute Profile.Username_.Edit first last bio:textarea dob:date` to generate a Route module `app/Route/Profile/Username_/Edit.elm`
with the wiring form a `Form`.

[Learn more about writing and running elm-pages Scripts for scaffolding](https://elm-pages.com/docs/elm-pages-scripts#scaffolding-a-route-module).

@docs Kind, provide, restArgsParser

@docs Context

@docs recordEncoder, fieldEncoder

-}

import Cli.Option
import Elm
import Elm.Annotation as Type
import Elm.Declare
import Elm.Op
import List.Extra
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
type alias Context =
    { errors : Elm.Expression
    , submitting : Elm.Expression
    , submitAttempted : Elm.Expression
    , data : Elm.Expression
    , expression : Elm.Expression
    }


formWithFields : Bool -> List ( String, Kind ) -> ({ formState : { errors : Elm.Expression, submitting : Elm.Expression, submitAttempted : Elm.Expression, data : Elm.Expression, expression : Elm.Expression }, params : List { name : String, kind : Kind, param : Elm.Expression } } -> Elm.Expression) -> { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
formWithFields elmCssView fields viewFn =
    Elm.Declare.function "form"
        []
        (\_ ->
            fields
                |> List.foldl
                    (\( fieldName, kind ) chain ->
                        chain
                            |> Elm.Op.pipe
                                (formField fieldName
                                    (case kind of
                                        FieldText ->
                                            formFieldText
                                                |> Elm.Op.pipe (formFieldRequired (Elm.string "Required"))

                                        FieldInt ->
                                            formFieldInt { invalid = \_ -> Elm.string "" }
                                                |> Elm.Op.pipe (formFieldRequired (Elm.string "Required"))

                                        FieldTextarea ->
                                            formFieldText
                                                |> Elm.Op.pipe (formFieldRequired (Elm.string "Required"))
                                                |> Elm.Op.pipe
                                                    (formFieldTextarea
                                                        { rows = Elm.nothing
                                                        , cols = Elm.nothing
                                                        }
                                                    )

                                        FieldFloat ->
                                            formFieldFloat { invalid = \_ -> Elm.string "" }
                                                |> Elm.Op.pipe (formFieldRequired (Elm.string "Required"))

                                        FieldTime ->
                                            formFieldTime { invalid = \_ -> Elm.string "" }
                                                |> Elm.Op.pipe (formFieldRequired (Elm.string "Required"))

                                        FieldDate ->
                                            formFieldDate { invalid = \_ -> Elm.string "" }
                                                |> Elm.Op.pipe (formFieldRequired (Elm.string "Required"))

                                        FieldCheckbox ->
                                            formFieldCheckbox
                                    )
                                )
                    )
                    (Elm.function (List.map fieldToParam fields)
                        (\params ->
                            Elm.record
                                [ ( "combine"
                                  , params
                                        |> List.foldl
                                            (\fieldExpression chain ->
                                                chain
                                                    |> Elm.Op.pipe (validationAndMap fieldExpression)
                                            )
                                            (Elm.val "ParsedForm"
                                                |> Elm.Op.pipe validationSucceed
                                            )
                                  )
                                , ( "view"
                                  , Elm.fn ( "formState", Nothing )
                                        (\formState ->
                                            let
                                                mappedParams : List { name : String, kind : Kind, param : Elm.Expression }
                                                mappedParams =
                                                    params
                                                        |> List.Extra.zip fields
                                                        |> List.map
                                                            (\( ( name, kind ), param ) ->
                                                                { name = name
                                                                , kind = kind
                                                                , param = param
                                                                }
                                                            )
                                            in
                                            viewFn
                                                { formState =
                                                    { errors = formState |> Elm.get "errors"
                                                    , submitting = formState |> Elm.get "submitting"
                                                    , submitAttempted = formState |> Elm.get "submitAttempted"
                                                    , data = formState |> Elm.get "data"
                                                    , expression = formState
                                                    }
                                                , params = mappedParams
                                                }
                                        )
                                  )
                                ]
                        )
                        |> Elm.Op.pipe formInit
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
                        , Type.namedWith [ "PagesMsg" ] "PagesMsg" [ Type.named [] "Msg" ]
                        ]
                    )
        )


fieldToParam : ( String, Kind ) -> ( String, Maybe Type.Annotation )
fieldToParam ( name, _ ) =
    ( name, Nothing )


{-| This parser handles the following field types (or `text` if none is provided):

  - `text`
  - `textarea`
  - `checkbox`
  - `time`
  - `date`

The naming convention follows the same naming as the HTML form field elements or attributes that are used to represent them.
In addition to using the appropriate field type, this will also give you an Elm type with the corresponding base type (like `Date` for `date` or `Bool` for `checkbox`).

-}
restArgsParser : Cli.Option.Option (List String) (List ( String, Kind )) Cli.Option.RestArgsOption
restArgsParser =
    Cli.Option.restArgs "formFields"
        |> Cli.Option.validateMap
            (\items ->
                items
                    |> List.map parseField
                    |> Result.Extra.combine
            )


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
        { formState : Context
        , params : List { name : String, kind : Kind, param : Elm.Expression }
        }
        -> Elm.Expression
    }
    ->
        Maybe
            { formHandlers : Elm.Expression
            , form : Elm.Expression
            , declarations : List Elm.Declaration
            }
provide { fields, view, elmCssView } =
    if List.isEmpty fields then
        Nothing

    else
        let
            form : { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
            form =
                formWithFields elmCssView fields view

            formHandlersDeclaration : { declaration : Elm.Declaration, call : List Elm.Expression -> Elm.Expression, callFrom : List String -> List Elm.Expression -> Elm.Expression, value : List String -> Elm.Expression }
            formHandlersDeclaration =
                -- TODO customizable formHandlers name?
                Elm.Declare.function "formHandlers"
                    []
                    (\_ ->
                        initCombined (Elm.val "Action") (form.call [])
                            |> Elm.withType
                                (Type.namedWith [ "Form", "Handler" ]
                                    "Handler"
                                    [ Type.string
                                    , Type.named [] "Action"
                                    ]
                                )
                    )
        in
        Just
            { formHandlers = formHandlersDeclaration.call []
            , form = form.call []
            , declarations =
                [ formWithFields elmCssView fields view |> .declaration
                , Elm.customType "Action"
                    [ Elm.variantWith "Action" [ Type.named [] "ParsedForm" ]
                    ]
                , formHandlersDeclaration.declaration

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


validationAndMap : Elm.Expression -> Elm.Expression
validationAndMap andMapArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Validation" ]
            , name = "andMap"
            , annotation = Nothing
            }
        )
        [ andMapArg ]


validationSucceed : Elm.Expression
validationSucceed =
    Elm.value
        { importFrom = [ "Form", "Validation" ]
        , name = "succeed"
        , annotation = Nothing
        }


formFieldText : Elm.Expression
formFieldText =
    Elm.value
        { importFrom = [ "Form", "Field" ]
        , name = "text"
        , annotation = Nothing
        }


formFieldRequired : Elm.Expression -> Elm.Expression
formFieldRequired requiredArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Field" ]
            , name = "required"
            , annotation = Nothing
            }
        )
        [ requiredArg ]


formFieldInt : { invalid : Elm.Expression -> Elm.Expression } -> Elm.Expression
formFieldInt intArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Field" ]
            , name = "int"
            , annotation =
                Nothing
            }
        )
        [ Elm.record
            [ Tuple.pair
                "invalid"
                (Elm.functionReduced "intUnpack" intArg.invalid)
            ]
        ]


formFieldTextarea :
    { rows : Elm.Expression, cols : Elm.Expression }
    -> Elm.Expression
formFieldTextarea textareaArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Field" ]
            , name = "textarea"
            , annotation = Nothing
            }
        )
        [ Elm.record
            [ Tuple.pair "rows" textareaArg.rows
            , Tuple.pair "cols" textareaArg.cols
            ]
        ]


formFieldTime : { invalid : Elm.Expression -> Elm.Expression } -> Elm.Expression
formFieldTime timeArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Field" ]
            , name = "time"
            , annotation = Nothing
            }
        )
        [ Elm.record
            [ Tuple.pair
                "invalid"
                (Elm.functionReduced "timeUnpack" timeArg.invalid)
            ]
        ]


formFieldDate : { invalid : Elm.Expression -> Elm.Expression } -> Elm.Expression
formFieldDate dateArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Field" ]
            , name = "date"
            , annotation = Nothing
            }
        )
        [ Elm.record
            [ Tuple.pair
                "invalid"
                (Elm.functionReduced "dateUnpack" dateArg.invalid)
            ]
        ]


formFieldCheckbox : Elm.Expression
formFieldCheckbox =
    Elm.value
        { importFrom = [ "Form", "Field" ]
        , name = "checkbox"
        , annotation = Nothing
        }


formFieldFloat : { invalid : Elm.Expression -> Elm.Expression } -> Elm.Expression
formFieldFloat floatArg =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Field" ]
            , name = "float"
            , annotation = Nothing
            }
        )
        [ Elm.record
            [ Tuple.pair
                "invalid"
                (Elm.functionReduced "floatUnpack" floatArg.invalid)
            ]
        ]


formField : String -> Elm.Expression -> Elm.Expression
formField fieldArg fieldArg0 =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form" ]
            , name = "field"
            , annotation = Nothing
            }
        )
        [ Elm.string fieldArg, fieldArg0 ]


formInit : Elm.Expression
formInit =
    Elm.value
        { importFrom = [ "Form" ]
        , name = "form"
        , annotation = Nothing
        }
        |> Elm.Op.pipe
            (Elm.apply
                (Elm.value
                    { importFrom = [ "Form" ]
                    , name = "hiddenKind"
                    , annotation = Nothing
                    }
                )
                [ Elm.tuple (Elm.string "kind") (Elm.string "regular")
                , Elm.string "Expected kind."
                ]
            )


initCombined : Elm.Expression -> Elm.Expression -> Elm.Expression
initCombined initCombinedArg initCombinedArg0 =
    Elm.apply
        (Elm.value
            { importFrom = [ "Form", "Handler" ]
            , name = "init"
            , annotation = Nothing
            }
        )
        [ initCombinedArg, initCombinedArg0 ]


{-| Generate a JSON Encoder for the form fields. This can be helpful for sending the validated form data through a
BackendTask.Custom or to an external API from your scaffolded Route Module code.
-}
recordEncoder : Elm.Expression -> List ( String, Kind ) -> Elm.Expression
recordEncoder record fields =
    fields
        |> List.map
            (\( field, kind ) ->
                Elm.tuple
                    (Elm.string field)
                    (fieldEncoder record field kind)
            )
        |> Elm.list
        |> List.singleton
        |> Elm.apply
            (Elm.value
                { importFrom = [ "Json", "Encode" ]
                , name = "object"
                , annotation =
                    Just
                        (Type.function
                            [ Type.list
                                (Type.tuple
                                    Type.string
                                    (Type.namedWith [ "Json", "Encode" ] "Value" [])
                                )
                            ]
                            (Type.namedWith [ "Json", "Encode" ] "Value" [])
                        )
                }
            )


{-| A lower-level, more granular version of `recordEncoder` - lets you generate a JSON Encoder `Expression` for an individual Field rather than a group of Fields.
-}
fieldEncoder : Elm.Expression -> String -> Kind -> Elm.Expression
fieldEncoder record name kind =
    Elm.apply
        (case kind of
            FieldInt ->
                encoder "int"

            FieldText ->
                encoder "string"

            FieldTextarea ->
                encoder "string"

            FieldFloat ->
                encoder "float"

            FieldTime ->
                -- TODO fix time encoder
                encoder "int"

            FieldDate ->
                -- TODO fix date encoder
                encoder "int"

            FieldCheckbox ->
                encoder "bool"
        )
        [ Elm.get name record ]


encoder : String -> Elm.Expression
encoder name =
    Elm.value
        { importFrom = [ "Json", "Encode" ]
        , name = name
        , annotation = Nothing
        }
