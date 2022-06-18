module FormParserTests exposing (all)

import Date exposing (Date)
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
    describe "Form Parser" <|
        let
            passwordConfirmationParser =
                FormParser.andThenNew
                    (\password passwordConfirmation ->
                        if password.value /= passwordConfirmation.value then
                            ( Nothing
                            , Dict.fromList
                                [ ( passwordConfirmation.name, [ "Must match password" ] )
                                ]
                            )

                        else
                            FormParser.ok { password = password.value }
                    )
                    (\fieldErrors password passwordConfirmation -> Div)
                    |> FormParser.field "password" (Field.text |> Field.required "Password is required")
                    |> FormParser.field "password-confirmation" (Field.text |> Field.required "Password confirmation is required")
        in
        [ test "matching password" <|
            \() ->
                FormParser.runServerSide
                    (fields
                        [ ( "password", "mypassword" )
                        , ( "password-confirmation", "mypassword" )
                        ]
                    )
                    passwordConfirmationParser
                    |> Expect.equal
                        ( Just { password = "mypassword" }
                        , Dict.empty
                        )
        , test "non-matching password" <|
            \() ->
                FormParser.runServerSide
                    (fields
                        [ ( "password", "mypassword" )
                        , ( "password-confirmation", "doesnt-match-password" )
                        ]
                    )
                    passwordConfirmationParser
                    |> Expect.equal
                        ( Nothing
                        , Dict.fromList [ ( "password-confirmation", [ "Must match password" ] ) ]
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
            , describe "dependent validations" <|
                let
                    --checkinFormParser : FormParser.HtmlForm String ( Date, Date ) data msg
                    checkinFormParser : FormParser.Form String ( Maybe ( Date, Date ), Dict String (List String) ) data (FormParser.Context String -> MyView)
                    checkinFormParser =
                        FormParser.andThenNew
                            (\checkin checkout ->
                                if Date.toRataDie checkin.value >= Date.toRataDie checkout.value then
                                    ( Just ( checkin.value, checkout.value )
                                    , Dict.fromList
                                        [ ( "checkin", [ "Must be before checkout" ] )
                                        ]
                                    )

                                else
                                    FormParser.ok ( checkin.value, checkout.value )
                            )
                            (\fieldErrors checkin checkout -> Div)
                            |> FormParser.field "checkin"
                                (Field.date { invalid = \_ -> "Invalid" } |> Field.required "Required")
                            |> FormParser.field "checkout"
                                (Field.date { invalid = \_ -> "Invalid" } |> Field.required "Required")
                in
                [ test "checkin must be before checkout" <|
                    \() ->
                        FormParser.runOneOfServerSide
                            (fields
                                [ ( "checkin", "2022-01-01" )
                                , ( "checkout", "2022-01-03" )
                                ]
                            )
                            [ checkinFormParser ]
                            |> Expect.equal
                                ( Just ( Date.fromRataDie 738156, Date.fromRataDie 738158 )
                                , Dict.empty
                                )
                , test "checkout is invalid because before checkin" <|
                    \() ->
                        FormParser.runServerSide
                            (fields
                                [ ( "checkin", "2022-01-03" )
                                , ( "checkout", "2022-01-01" )
                                ]
                            )
                            checkinFormParser
                            |> Expect.equal
                                ( Just ( Date.fromRataDie 738158, Date.fromRataDie 738156 )
                                  --( Just (Date.fromRataDie 738158)
                                , Dict.fromList
                                    [ ( "checkin", [ "Must be before checkout" ] )
                                    ]
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
