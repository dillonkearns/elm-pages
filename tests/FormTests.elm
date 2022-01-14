module FormTests exposing (all)

import Dict
import Expect
import Form
import Test exposing (Test, describe, only, skip, test)


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
                    |> Form.with (Form.text "first" toInput)
                    |> Form.runClientValidations
                        { fields =
                            Dict.fromList
                                [ ( "first", field "Jane" )
                                ]
                        , isSubmitting = Form.NotSubmitted
                        }
                    |> expectDecodeNoErrors "Jane"
        , test "run a single field's validation on blur" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.date "dob"
                            { invalid = \_ -> "Invalid date"
                            }
                            toInput
                        )
                    |> Form.runClientValidations
                        { fields =
                            Dict.fromList
                                [ ( "dob"
                                  , field "This is not a valid date"
                                  )
                                ]
                        , isSubmitting = Form.NotSubmitted
                        }
                    |> Expect.equal
                        (Err [ ( "dob", [ "Invalid date" ] ) ])
        , test "custom client validation" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.text "first" toInput
                            |> Form.withClientValidation
                                (\first ->
                                    if first |> String.toList |> List.head |> Maybe.withDefault 'a' |> Char.isUpper then
                                        Ok first

                                    else
                                        Err "Needs to be capitalized"
                                )
                        )
                    |> Form.runClientValidations
                        { fields =
                            Dict.fromList
                                [ ( "first", field "jane" )
                                ]
                        , isSubmitting = Form.NotSubmitted
                        }
                    |> Expect.equal
                        (Err
                            [ ( "first", [ "Needs to be capitalized" ] )
                            ]
                        )
        , test "init dict includes default values" <|
            \() ->
                Form.succeed identity
                    |> Form.with
                        (Form.text "first" toInput
                            |> Form.withInitialValue "Jane"
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
                            |> Form.withInitialValue "Jane"
                            |> Form.withClientValidation (\_ -> Err "This error always occurs")
                        )
                    |> Form.init
                    |> Form.hasErrors2
                    |> Expect.true "expected errors"
        , skip <|
            test "dependent validations" <|
                \() ->
                    Form.succeed Tuple.pair
                        |> Form.with
                            (Form.requiredDate "checkin"
                                { invalid = \_ -> "Invalid date"
                                , missing = "Required"
                                }
                                toInput
                                |> Form.withInitialValue "2022-01-01"
                            )
                        |> Form.with
                            (Form.requiredDate "checkout"
                                { invalid = \_ -> "Invalid date"
                                , missing = "Required"
                                }
                                toInput
                                |> Form.withInitialValue "2022-01-01"
                            )
                        |> Form.validate
                            (\( checkin, checkout ) ->
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
        , skip <|
            test "form-level validations are when there are recoverable field-level errors" <|
                \() ->
                    let
                        form =
                            Form.succeed Tuple.pair
                                |> Form.with
                                    (Form.text "password" toInput
                                        |> Form.required "Required"
                                    )
                                |> Form.with
                                    (Form.text "password-confirmation" toInput
                                        |> Form.required "Required"
                                    )
                                |> Form.validate
                                    (\( password, passwordConfirmation ) ->
                                        if password == passwordConfirmation then
                                            []

                                        else
                                            [ ( "password-confirmation", [ "Passwords must match." ] )
                                            ]
                                    )
                                |> Form.appendForm Tuple.pair
                                    (Form.succeed identity
                                        |> Form.with
                                            (Form.text "name" toInput
                                                |> Form.required "Required"
                                            )
                                    )
                    in
                    form
                        |> Form.init
                        |> updateField form ( "password", "abcd" )
                        |> updateField form ( "password-confirmation", "abcd" )
                        |> expectErrors
                            [ ( "name", [ "Required" ] )
                            , ( "password", [] )
                            , ( "password-confirmation", [ "Passwords must match." ] )
                            ]
        , skip <|
            test "dependent validations are run when other fields have recoverable errors" <|
                \() ->
                    Form.succeed Tuple.pair
                        |> Form.with
                            (Form.requiredDate "checkin"
                                { invalid = \_ -> "Invalid date"
                                , missing = "Required"
                                }
                                toInput
                                |> Form.withInitialValue "2022-01-01"
                            )
                        |> Form.with
                            (Form.requiredDate "checkout"
                                { invalid = \_ -> "Invalid date"
                                , missing = "Required"
                                }
                                toInput
                                |> Form.withInitialValue "2022-01-01"
                            )
                        |> Form.validate
                            (\( checkin, checkout ) ->
                                [ ( "checkin", [ "Must be before checkout date." ] )
                                ]
                            )
                        |> Form.appendForm Tuple.pair
                            (Form.succeed identity
                                |> Form.with
                                    (Form.text "name" toInput
                                        |> Form.required "Required"
                                    )
                            )
                        |> expectErrorsAfterUpdates
                            [ ( "checkin", [ "Must be before checkout date." ] )
                            , ( "checkout", [] )
                            , ( "name", [ "Required" ] )
                            ]
        ]


expectDecodeNoErrors : decoded -> Result error ( decoded, List b ) -> Expect.Expectation
expectDecodeNoErrors decoded actual =
    actual
        |> Expect.equal (Ok ( decoded, [] ))


updateField : Form.Form String value view -> ( String, String ) -> Form.Model -> Form.Model
updateField form ( name, value ) model =
    model
        |> Form.update (\_ -> ()) (\_ -> ()) form (Form.OnFieldInput { name = name, value = value })
        |> Tuple.first


expectErrors : List ( String, List String ) -> Form.Model -> Expect.Expectation
expectErrors expected form =
    form.fields
        |> Dict.map (\key value -> value.errors)
        |> Expect.equalDicts (Dict.fromList expected)


updateAllFields : List String -> Form.Form String value view -> Form.Model -> Form.Model
updateAllFields fields form model =
    fields
        |> List.foldl
            (\fieldName modelSoFar ->
                modelSoFar
                    |> updateField form ( fieldName, "" )
            )
            model


expectErrorsAfterUpdates : List ( String, List String ) -> Form.Form String value view -> Expect.Expectation
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
                        |> Dict.map (\key value -> value.errors)
                        |> Expect.equalDicts (Dict.fromList expected)
                )
        )
        ()


field value =
    { raw = Just value, errors = [], status = Form.NotVisited }


toInput _ =
    ()
