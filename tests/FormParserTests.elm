module FormParserTests exposing (all)

import Dict exposing (Dict)
import Expect
import Pages.Field as Field
import Pages.Form
import Pages.FormParser as FormParser exposing (field)
import Test exposing (Test, describe, test)


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
                FormParser.runServerSide
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
                        ( Just { password = "mypassword" }
                        , Dict.fromList
                            [ ( "password", [] )
                            , ( "password-confirmation", [] )
                            ]
                        )
        , describe "oneOf" <|
            let
                oneOfParsers =
                    [ FormParser.andThenNew
                        (\_ -> FormParser.ok Signout)
                        (\fieldErrors -> Div)
                        |> FormParser.hiddenField "kind" (Field.exactValue "signout" "Expected signout")
                    , FormParser.andThenNew
                        (\_ uuid quantity ->
                            SetQuantity (Uuid uuid.value) quantity.value
                                |> FormParser.ok
                        )
                        (\fieldErrors quantity -> Div)
                        |> FormParser.hiddenField "kind" (Field.exactValue "setQuantity" "Expected setQuantity")
                        |> FormParser.hiddenField "uuid" (Field.text |> Field.required "Required")
                        |> FormParser.field "quantity" (Field.int { invalid = \_ -> "Expected int" } |> Field.required "Required")
                    ]
            in
            [ test "first branch" <|
                \() ->
                    FormParser.runOneOfServerSide
                        (fields
                            [ ( "kind", "signout" )
                            ]
                        )
                        oneOfParsers
                        |> Expect.equal
                            ( Just Signout
                            , Dict.empty
                            )
            , test "second branch" <|
                \() ->
                    FormParser.runOneOfServerSide
                        (fields
                            [ ( "kind", "setQuantity" )
                            , ( "uuid", "123" )
                            , ( "quantity", "1" )
                            ]
                        )
                        oneOfParsers
                        |> Expect.equal
                            ( Just (SetQuantity (Uuid "123") 1)
                            , Dict.empty
                            )

            --, test "no match" <|
            --    \() ->
            --        FormParser.runOneOfServerSide
            --            (fields [])
            --            oneOfParsers
            --            |> Expect.equal
            --                ( Nothing
            --                , Dict.fromList []
            --                )
            , describe "select" <|
                let
                    selectParser =
                        [ FormParser.andThenNew
                            (\media ->
                                media.value
                                    |> FormParser.ok
                            )
                            (\fieldErrors media -> Div)
                            |> FormParser.field "media"
                                (Field.select
                                    [ ( "book", Book )
                                    , ( "article", Article )
                                    , ( "video", Video )
                                    ]
                                    (\_ -> "Invalid")
                                )
                        ]
                in
                [ test "example" <|
                    \() ->
                        FormParser.runOneOfServerSide
                            (fields
                                [ ( "media", "book" )
                                ]
                            )
                            selectParser
                            |> Expect.equal
                                ( Just (Just Book)
                                , Dict.empty
                                )
                ]
            ]
        ]


type Media
    = Book
    | Article
    | Video


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


fields : List ( String, String ) -> List ( String, String )
fields list =
    list
