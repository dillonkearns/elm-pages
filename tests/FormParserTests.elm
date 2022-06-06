module FormParserTests exposing (all)

import Dict exposing (Dict)
import Expect
import Pages.Form
import Pages.FormParser as FormParser exposing (field)
import Test exposing (Test, describe, test)


formDecoder : FormParser.Parser String ( String, String )
formDecoder =
    FormParser.map2 Tuple.pair
        (FormParser.required "first" "First is required")
        (FormParser.required "last" "Last is required")


type Uuid
    = Uuid String


type Action
    = Signout
    | SetQuantity Uuid Int


all : Test
all =
    describe "Form Parser"
        [ test "new design idea with errors" <|
            \() ->
                FormParser.runNew
                    (fields
                        [ ( "password", "mypassword" )
                        , ( "password-confirmation", "my-password" )
                        ]
                    )
                    (FormParser.andThenNew
                        (\password passwordConfirmation ->
                            if password.value == passwordConfirmation.value then
                                passwordConfirmation |> FormParser.withError "Must match password"

                            else
                                FormParser.ok
                        )
                        |> FormParser.field "password" (FormParser.string "Password is required")
                        |> FormParser.field "password-confirmation" (FormParser.string "Password confirmation is required")
                    )
                    |> Expect.equal
                        ( Nothing
                        , Dict.fromList
                            [ ( "password-confirmation", [ "Must match password" ] )
                            ]
                        )
        , test "new design idea no errors" <|
            \() ->
                FormParser.runNew
                    (fields
                        [ ( "password", "mypassword" )
                        , ( "password-confirmation", "my-password" )
                        ]
                    )
                    (FormParser.andThenNew
                        (\password passwordConfirmation ->
                            if password.value == passwordConfirmation.value then
                                passwordConfirmation |> FormParser.withError "Must match password"

                            else
                                FormParser.ok
                        )
                        |> FormParser.field "password" (FormParser.string "Password is required")
                        |> FormParser.field "password-confirmation" (FormParser.string "Password confirmation is required")
                    )
                    |> Expect.equal
                        ( Just ()
                        , Dict.fromList []
                        )
        ]


field : String -> String -> ( String, Pages.Form.FieldState )
field name value =
    ( name
    , { value = value
      , status = Pages.Form.NotVisited
      }
    )


fields : List ( String, String ) -> Dict String Pages.Form.FieldState
fields list =
    list
        |> List.map (\( name, value ) -> field name value)
        |> Dict.fromList
