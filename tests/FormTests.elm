module FormTests exposing (all)

import Dict
import Expect
import Form
import Test exposing (describe, only, skip, test)


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
                    |> Expect.equal
                        (Ok ())
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
                    |> Expect.equal
                        (Ok "Jane")
        , test "run a single field's validation on blur" <|
            \() ->
                Form.succeed identity
                    |> Form.with (Form.date "dob" toInput)
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
                        (Err [ ( "dob", [ Form.InvalidDate ] ) ])
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
                            [ ( "first", [ Form.Error "Needs to be capitalized" ] )
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
        , test "dependent validations" <|
            \() ->
                Form.succeed Tuple.pair
                    |> Form.with
                        (Form.requiredDate "checkin" toInput
                            |> Form.withInitialValue "2022-01-01"
                        )
                    |> Form.with
                        (Form.requiredDate "checkout" toInput
                            |> Form.withInitialValue "2022-01-01"
                        )
                    |> Form.validate
                        (\( checkin, checkout ) ->
                            [ ( "checkin", [ Form.Error "Must be before checkout date." ] )
                            ]
                        )
                    |> Form.init
                    |> expectErrors
                        [ ( "checkin", [ Form.Error "Must be before checkout date." ] )
                        , ( "checkout", [] )
                        ]
        , test "initial validations only run once" <|
            \() ->
                (Form.succeed identity
                    |> Form.with
                        (Form.text "name" toInput
                            |> Form.required
                        )
                )
                    |> Form.init
                    |> expectErrors
                        [ ( "name", [ Form.MissingRequired ] )
                        ]
        , test "no duplicate validation errors from update call" <|
            \() ->
                let
                    form =
                        Form.succeed identity
                            |> Form.with
                                (Form.text "name" toInput
                                    |> Form.required
                                )
                in
                form
                    |> Form.init
                    |> updateField form ( "name", "" )
                    |> expectErrors
                        [ ( "name", [ Form.MissingRequired ] )
                        ]
        , skip <|
            test "form-level validations are when there are recoverable field-level errors" <|
                \() ->
                    let
                        form =
                            Form.succeed Tuple.pair
                                |> Form.with
                                    (Form.text "password" toInput
                                        |> Form.required
                                    )
                                |> Form.with
                                    (Form.text "password-confirmation" toInput
                                        |> Form.required
                                    )
                                |> Form.validate
                                    (\( password, passwordConfirmation ) ->
                                        if password == passwordConfirmation then
                                            []

                                        else
                                            [ ( "password-confirmation", [ Form.Error "Passwords must match." ] )
                                            ]
                                    )
                                |> Form.appendForm Tuple.pair
                                    (Form.succeed identity
                                        |> Form.with
                                            (Form.text "name" toInput
                                                |> Form.required
                                            )
                                    )
                    in
                    form
                        |> Form.init
                        |> updateField form ( "password", "abcd" )
                        |> updateField form ( "password-confirmation", "abcd" )
                        |> expectErrors
                            [ ( "name", [ Form.MissingRequired ] )
                            , ( "password", [] )
                            , ( "password-confirmation", [ Form.Error "Passwords must match." ] )
                            ]
        , skip <|
            test "dependent validations are run when other fields have recoverable errors" <|
                \() ->
                    Form.succeed Tuple.pair
                        |> Form.with
                            (Form.requiredDate "checkin" toInput
                                |> Form.withInitialValue "2022-01-01"
                            )
                        |> Form.with
                            (Form.requiredDate "checkout" toInput
                                |> Form.withInitialValue "2022-01-01"
                            )
                        |> Form.validate
                            (\( checkin, checkout ) ->
                                [ ( "checkin", [ Form.Error "Must be before checkout date." ] )
                                ]
                            )
                        |> Form.appendForm Tuple.pair
                            (Form.succeed identity
                                |> Form.with
                                    (Form.text "name" toInput
                                        |> Form.required
                                    )
                            )
                        |> Form.init
                        |> expectErrors
                            [ ( "checkin", [ Form.Error "Must be before checkout date." ] )
                            , ( "checkout", [] )
                            , ( "name", [ Form.MissingRequired ] )
                            ]
        ]


updateField : Form.Form value view -> ( String, String ) -> Form.Model -> Form.Model
updateField form ( name, value ) model =
    model
        |> Form.update (\_ -> ()) (\_ -> ()) form (Form.OnFieldInput { name = name, value = value })
        |> Tuple.first


expectErrors : List ( String, List Form.Error ) -> Form.Model -> Expect.Expectation
expectErrors expected form =
    form.fields
        |> Dict.map (\key value -> value.errors)
        |> Expect.equalDicts (Dict.fromList expected)


field value =
    { raw = Just value, errors = [], status = Form.NotVisited }


toInput _ =
    ()
