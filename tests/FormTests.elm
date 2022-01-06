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
        ]


toInput _ =
    ()
