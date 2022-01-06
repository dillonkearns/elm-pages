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
        ]


toInput _ =
    ()
