module FormTests exposing (all)

import Dict
import Expect
import Form
import Test exposing (describe, test)


all =
    describe "Form"
        [ test "succeed" <|
            \() ->
                Form.succeed ()
                    |> Form.runClientValidations Form.init
                    |> Expect.equal
                        (Ok ())
        , test "single field" <|
            \() ->
                Form.succeed identity
                    |> Form.with (Form.text "first" toInput)
                    |> Form.runClientValidations
                        (Dict.fromList
                            [ ( "first"
                              , { raw = Just "Jane", errors = [] }
                              )
                            ]
                        )
                    |> Expect.equal
                        (Ok "Jane")
        , test "run a single field's validation on blur" <|
            \() ->
                Form.succeed identity
                    |> Form.with (Form.date "dob" toInput)
                    |> Form.runClientValidations
                        (Dict.fromList
                            [ ( "dob"
                              , { raw = Just "This is not a valid date", errors = [] }
                              )
                            ]
                        )
                    |> Expect.equal
                        (Err [ "Expected a date in ISO 8601 format" ])
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
                        (Dict.fromList
                            [ ( "first"
                              , { raw = Just "jane", errors = [] }
                              )
                            ]
                        )
                    |> Expect.equal
                        (Err [ "Needs to be capitalized" ])
        ]


toInput _ =
    ()
