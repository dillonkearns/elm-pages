module OldFormTests exposing (all)

import Date
import Dict
import Expect
import Form
import Form.Value
import Test exposing (Test, describe, test)
import Time


all : Test
all =
    describe "Form"
        [ test "succeed" <|
            \() ->
                let
                    form =
                        Form.succeed ()
                in
                form
                    |> Form.runClientValidations (Form.init form)
                    |> expectDecodeNoErrors ()
        , test "single field" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.text "first" toInput
                            |> Form.required "Required"
                        )
                    |> Form.runClientValidations
                        { fields =
                            Dict.fromList
                                [ ( "first", field "Jane" )
                                ]
                        , isSubmitting = Form.NotSubmitted
                        , formErrors = Dict.empty
                        }
                    |> expectDecodeNoErrors "Jane"
        , test "run a single field's validation on blur" <|
            \() ->
                let
                    form =
                        Form.succeed identity
                            |> Form.with
                                (Form.date "dob"
                                    { invalid = \_ -> "Invalid date"
                                    }
                                    toInput
                                )
                in
                form
                    |> Form.init
                    |> updateField form ( "dob", "This is not a valid date" )
                    |> expectErrors
                        [ ( "dob", [ "Invalid date" ] ) ]
        , test "custom client validation" <|
            \() ->
                let
                    form =
                        Form.succeed identity
                            |> Form.with
                                (Form.text "first" toInput
                                    |> Form.required "Required"
                                    |> Form.withClientValidation
                                        (\first ->
                                            if first |> String.toList |> List.head |> Maybe.withDefault 'a' |> Char.isUpper then
                                                Ok first

                                            else
                                                Err "Needs to be capitalized"
                                        )
                                )
                in
                form
                    |> Form.init
                    |> updateField form ( "first", "jane" )
                    |> expectErrors
                        [ ( "first", [ "Needs to be capitalized" ] ) ]
        , test "init dict includes default values" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.text "first" toInput
                            |> Form.withInitialValue ("Jane" |> Form.Value.string)
                        )
                    |> Form.init
                    |> Form.rawValues
                    |> Expect.equal
                        (Dict.fromList [ ( "first", "Jane" ) ])
        , test "client validations are available on init" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.text "first" toInput
                            |> Form.withInitialValue ("Jane" |> Form.Value.string)
                            |> Form.withClientValidation (\_ -> Err "This error always occurs")
                        )
                    |> Form.init
                    |> Form.hasErrors
                    |> Expect.true "expected errors"
        , test "dependent validations" <|
            \() ->
                Form.succeed Tuple.pair
                    |> Form.with
                        (Form.date "checkin"
                            { invalid = \_ -> "Invalid date" }
                            toInput
                            |> Form.required "Required"
                            |> Form.withInitialValue (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
                        )
                    |> Form.with
                        (Form.date "checkout"
                            { invalid = \_ -> "Invalid date" }
                            toInput
                            |> Form.required "Required"
                            |> Form.withInitialValue (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
                        )
                    |> Form.validate
                        (\_ ->
                            [ ( "checkin", [ "Must be before checkout date." ] )
                            ]
                        )
                    |> Form.init
                    |> expectErrors
                        [ ( "checkin", [ "Must be before checkout date." ] )
                        , ( "checkout", [] )
                        ]
        , test "initial validations only run once" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.text "name" toInput
                            |> Form.required "Required"
                        )
                    |> expectErrorsAfterUpdates
                        [ ( "name", [ "Required" ] )
                        ]
        , test "parses time" <|
            \() ->
                let
                    form =
                        Form.succeed identity
                            |> Form.with
                                (Form.time "checkin-time"
                                    { invalid = \_ -> "Invalid time" }
                                    toInput
                                    |> Form.required "Required"
                                )
                in
                form
                    |> expectDecodeNoErrors2 [ ( "checkin-time", "08:45" ) ]
                        { hours = 8
                        , minutes = 45
                        }
        , test "no duplicate validation errors from update call" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.text "name" toInput
                            |> Form.required "Required"
                        )
                    |> expectErrorsAfterUpdates
                        [ ( "name", [ "Required" ] )
                        ]
        , test "runs proceeding validations even when there are prior errors" <|
            \() ->
                Form.succeed Tuple.pair
                    |> Form.with
                        (Form.text "first" toInput
                            |> Form.required "Required"
                        )
                    |> Form.with
                        (Form.text "last" toInput
                            |> Form.required "Required"
                        )
                    |> expectErrorsAfterUpdates
                        [ ( "first", [ "Required" ] )
                        , ( "last", [ "Required" ] )
                        ]

        --, test "form-level validations are run when there are recoverable field-level errors" <|
        --    \() ->
        --        let
        --            form =
        --                Form.succeed Tuple.pair
        --                    |> Form.with
        --                        (Form.text "password" toInput
        --                            |> Form.required "Required"
        --                        )
        --                    |> Form.with
        --                        (Form.text "password-confirmation" toInput
        --                            |> Form.required "Required"
        --                        )
        --                    |> Form.validate
        --                        (\( password, passwordConfirmation ) ->
        --                            if password == passwordConfirmation then
        --                                []
        --
        --                            else
        --                                [ ( "password-confirmation", [ "Passwords must match." ] )
        --                                ]
        --                        )
        --                    |> Form.appendForm Tuple.pair
        --                        (Form.succeed identity
        --                            |> Form.with
        --                                (Form.text "name" toInput
        --                                    |> Form.required "Required"
        --                                )
        --                        )
        --        in
        --        form
        --            |> Form.init
        --            |> updateField form ( "password", "abcd" )
        --            |> updateField form ( "password-confirmation", "abcd" )
        --            |> expectErrors
        --                [ ( "name", [ "Required" ] )
        --                , ( "password", [] )
        --                , ( "password-confirmation", [ "Passwords must match." ] )
        --                ]
        --, test "dependent validations are run when other fields have recoverable errors" <|
        --    \() ->
        --        Form.succeed Tuple.pair
        --            |> Form.with
        --                (Form.date "checkin"
        --                    { invalid = \_ -> "Invalid date" }
        --                    toInput
        --                    |> Form.required "Required"
        --                    |> Form.withInitialValue (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
        --                )
        --            |> Form.with
        --                (Form.date "checkout"
        --                    { invalid = \_ -> "Invalid date" }
        --                    toInput
        --                    |> Form.required "Required"
        --                    |> Form.withInitialValue (Date.fromCalendarDate 2022 Time.Jan 1 |> Form.Value.date)
        --                )
        --            |> Form.validate
        --                (\_ ->
        --                    [ ( "checkin", [ "Must be before checkout date." ] )
        --                    ]
        --                )
        --            |> Form.appendForm Tuple.pair
        --                (Form.succeed identity
        --                    |> Form.with
        --                        (Form.text "name" toInput
        --                            |> Form.required "Required"
        --                        )
        --                )
        --            |> expectErrorsAfterUpdates
        --                [ ( "checkin", [ "Must be before checkout date." ] )
        --                , ( "checkout", [] )
        --                , ( "name", [ "Required" ] )
        --                ]
        , test "min validation runs in pure elm" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.range "rating"
                            { missing = "Missing"
                            , invalid = \_ -> "Invalid"
                            }
                            { initial = 3, min = 1, max = 5 }
                            toInput
                        )
                    |> performUpdatesThenExpectErrors
                        [ ( "rating", "-1" ) ]
                        [ ( "rating", [ "Invalid" ] )
                        ]
        , test "invalid floats give error for float input" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.float "factor"
                            { invalid = \_ -> "Invalid"
                            }
                            toInput
                        )
                    |> performUpdatesThenExpectErrors
                        [ ( "factor", "abc" ) ]
                        [ ( "factor", [ "Invalid" ] )
                        ]
        , test "invalid ints give error for float input" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.int "factor"
                            { invalid = \_ -> "Invalid"
                            }
                            toInput
                        )
                    |> performUpdatesThenExpectErrors
                        [ ( "factor", "abc" ) ]
                        [ ( "factor", [ "Invalid" ] )
                        ]
        ]


expectDecodeNoErrors2 : List ( String, String ) -> decoded -> Form.Form () String decoded view -> Expect.Expectation
expectDecodeNoErrors2 updates expected form =
    let
        formModel =
            form
                |> Form.init
                |> updateFieldsWithValues updates form
    in
    Form.runClientValidations formModel form
        |> Expect.equal
            (Ok ( expected, [] ))


expectDecodeNoErrors : decoded -> Result error ( decoded, List b ) -> Expect.Expectation
expectDecodeNoErrors decoded actual =
    actual
        |> Expect.equal (Ok ( decoded, [] ))


updateField : Form.Form () String value view -> ( String, String ) -> Form.Model -> Form.Model
updateField form ( name, value ) model =
    model
        |> Form.update (\_ -> ()) () (\_ -> ()) form (Form.OnFieldInput { name = name, value = value })
        |> Tuple.first


expectErrors : List ( String, List String ) -> Form.Model -> Expect.Expectation
expectErrors expected form =
    form.fields
        |> Dict.map
            (\key value ->
                value.errors
                    ++ (form.formErrors
                            |> Dict.get key
                            |> Maybe.withDefault []
                       )
            )
        |> Expect.equalDicts (Dict.fromList expected)


updateAllFields : List String -> Form.Form () String value view -> Form.Model -> Form.Model
updateAllFields fields form model =
    fields
        |> List.foldl
            (\fieldName modelSoFar ->
                modelSoFar
                    |> updateField form ( fieldName, "" )
            )
            model


updateFieldsWithValues : List ( String, String ) -> Form.Form () String value view -> Form.Model -> Form.Model
updateFieldsWithValues fields form model =
    fields
        |> List.foldl
            (\( fieldName, fieldValue ) modelSoFar ->
                modelSoFar
                    |> updateField form ( fieldName, fieldValue )
            )
            model


expectErrorsAfterUpdates : List ( String, List String ) -> Form.Form () String value view -> Expect.Expectation
expectErrorsAfterUpdates expected form =
    let
        fieldsToUpdate : List String
        fieldsToUpdate =
            expected |> List.map Tuple.first

        model : Form.Model
        model =
            Form.init form
    in
    Expect.all
        ([ model
         , updateAllFields fieldsToUpdate form model
         ]
            |> List.map
                (\formModel () ->
                    formModel.fields
                        |> Dict.map (\_ value -> value.errors)
                        |> Expect.equalDicts (Dict.fromList expected)
                )
        )
        ()


performUpdatesThenExpectErrors : List ( String, String ) -> List ( String, List String ) -> Form.Form () String value view -> Expect.Expectation
performUpdatesThenExpectErrors updatesToPerform expected form =
    let
        model : Form.Model
        model =
            Form.init form
    in
    Expect.all
        ([ updateFieldsWithValues updatesToPerform form model
         ]
            |> List.map
                (\formModel () ->
                    formModel.fields
                        |> Dict.map (\_ value -> value.errors)
                        |> Expect.equalDicts (Dict.fromList expected)
                )
        )
        ()


field : a -> { raw : Maybe a, errors : List b, status : Form.FieldStatus }
field value =
    { raw = Just value, errors = [], status = Form.NotVisited }


toInput : a -> ()
toInput _ =
    ()
