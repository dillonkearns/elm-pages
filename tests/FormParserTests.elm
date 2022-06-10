module FormParserTests exposing (all)

import Dict exposing (Dict)
import Expect
import Pages.Field as Field
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
        [ --test "new design idea with errors" <|
          --    \() ->
          --        FormParser.runNew
          --            (fields
          --                [ ( "password", "mypassword" )
          --                , ( "password-confirmation", "my-password" )
          --                ]
          --            )
          --            (FormParser.andThenNew
          --                (\password passwordConfirmation ->
          --                    if password.value == passwordConfirmation.value then
          --                        passwordConfirmation |> FormParser.withError "Must match password"
          --
          --                    else
          --                        FormParser.ok
          --                )
          --                |> FormParser.field "password" (FormParser.string "Password is required")
          --                |> FormParser.field "password-confirmation" (FormParser.string "Password confirmation is required")
          --            )
          --            |> Expect.equal
          --                ( Nothing
          --                , Dict.fromList
          --                    [ ( "password-confirmation", [ "Must match password" ] )
          --                    ]
          --                )
          --test "non-dependent field error" <|
          --  \() ->
          --      FormParser.runNew
          --          (fields
          --              [ ( "password", "mypassword" )
          --              , ( "password-confirmation", "" )
          --              ]
          --          )
          --          (FormParser.andThenNew
          --              (\password passwordConfirmation ->
          --                  if password.value == passwordConfirmation.value then
          --                      --passwordConfirmation |> FormParser.withError "Must match password"
          --                      Debug.todo ""
          --
          --                  else
          --                      FormParser.ok { password = password }
          --              )
          --              |> FormParser.field "password" (FormParser.requiredString "Password is required")
          --              |> FormParser.field "password-confirmation" (FormParser.requiredString "Password confirmation is required")
          --          )
          --          |> Expect.equal
          --              ( Nothing
          --              , Dict.fromList
          --                  [ ( "password", [] )
          --                  , ( "password-confirmation", [ "Password confirmation is required" ] )
          --                  ]
          --              ),
          test "new design idea 3" <|
            \() ->
                FormParser.runNew
                    (fields
                        [ ( "password", "mypassword" )
                        , ( "password-confirmation", "mypassword" )
                        ]
                    )
                    (FormParser.andThenNew
                        (\password passwordConfirmation ->
                            if password.value /= passwordConfirmation.value then
                                Debug.todo ""
                                --passwordConfirmation |> FormParser.withError "Must match password"

                            else
                                FormParser.ok { password = password.value }
                        )
                        (\fieldErrors password passwordConfirmation ->
                            Div
                         --Html.form []
                         --    [ password |> FormParser.input []
                         --    , passwordConfirmation |> FormParser.input []
                         --    ]
                         --}
                        )
                        |> FormParser.field "password" (Field.text |> Field.required "Password is required")
                        |> FormParser.field "password-confirmation" (Field.text |> Field.required "Password confirmation is required")
                    )
                    |> Expect.equal
                        { result =
                            ( Just { password = "mypassword" }
                            , Dict.fromList
                                [ ( "password", [] )
                                , ( "password-confirmation", [] )
                                ]
                            )
                        , view = Div
                        }

        --|> expectNoErrors { password = "mypassword" }
        ]


type MyView
    = Div


expectNoErrors : parsed -> ( Maybe parsed, Dict String (List error) ) -> Expect.Expectation
expectNoErrors parsed =
    Expect.all
        [ Tuple.first
            >> Expect.equal
                (Just parsed)
        , Tuple.second
            >> Dict.values
            >> List.all List.isEmpty
            >> Expect.true "Expected no errors"
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
