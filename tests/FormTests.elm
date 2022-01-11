module FormTests exposing (all)

import Dict
import Expect
import Form
import Test exposing (describe, test)


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
                                [ ( "first"
                                  , { raw = Just "Jane", errors = [] }
                                  )
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
                                  , { raw = Just "This is not a valid date", errors = [] }
                                  )
                                ]
                        , isSubmitting = Form.NotSubmitted
                        }
                    |> Expect.equal
                        (Err [ Form.InvalidDate ])
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
                                [ ( "first"
                                  , { raw = Just "jane", errors = [] }
                                  )
                                ]
                        , isSubmitting = Form.NotSubmitted
                        }
                    |> Expect.equal
                        (Err [ Form.Error "Needs to be capitalized" ])
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
        ]


toInput _ =
    ()
