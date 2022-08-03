module FormTests exposing (all)

import Date exposing (Date)
import Dict
import Expect
import Form exposing (Form)
import Form.Field as Field
import Form.Validation as Validation exposing (Combined)
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
                Form.init
                    (\password passwordConfirmation ->
                        { combine =
                            Validation.succeed
                                (\passwordValue passwordConfirmationValue ->
                                    Validation.succeed { password = passwordValue }
                                        |> Validation.withErrorIf (passwordValue /= passwordConfirmationValue)
                                            passwordConfirmation
                                            "Must match password"
                                )
                                |> Validation.andMap password
                                |> Validation.andMap passwordConfirmation
                                |> Validation.andThen identity
                        , view = \_ -> Div
                        }
                    )
                    |> Form.field "password" (Field.text |> Field.required "Password is required")
                    |> Form.field "password-confirmation" (Field.text |> Field.required "Password confirmation is required")
        in
        [ test "matching password" <|
            \() ->
                Form.runServerSide
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
                Form.runServerSide
                    (fields
                        [ ( "password", "mypassword" )
                        , ( "password-confirmation", "doesnt-match-password" )
                        ]
                    )
                    passwordConfirmationParser
                    |> Expect.equal
                        ( Just { password = "mypassword" }
                        , Dict.fromList [ ( "password-confirmation", [ "Must match password" ] ) ]
                        )
        , describe "oneOf" <|
            let
                oneOfParsers =
                    [ Form.init
                        (\_ ->
                            { combine = Validation.succeed Signout
                            , view = \_ -> Div
                            }
                        )
                        |> Form.hiddenField "kind" (Field.exactValue "signout" "Expected signout")
                    , Form.init
                        (\_ uuid quantity ->
                            { combine =
                                Validation.succeed SetQuantity
                                    |> Validation.andMap (uuid |> Validation.map Uuid)
                                    |> Validation.andMap quantity
                            , view =
                                \_ -> Div
                            }
                        )
                        |> Form.hiddenField "kind" (Field.exactValue "setQuantity" "Expected setQuantity")
                        |> Form.hiddenField "uuid" (Field.text |> Field.required "Required")
                        |> Form.field "quantity" (Field.int { invalid = \_ -> "Expected int" } |> Field.required "Required")
                    ]
            in
            [ test "first branch" <|
                \() ->
                    Form.runOneOfServerSide
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
                    Form.runOneOfServerSide
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
            --        Form.runOneOfServerSide
            --            (fields [])
            --            oneOfParsers
            --            |> Expect.equal
            --                ( Nothing
            --                , Dict.fromList []
            --                )
            , describe "select" <|
                let
                    selectParser =
                        [ Form.init
                            (\media ->
                                { combine = media
                                , view =
                                    \_ -> Div
                                }
                            )
                            |> Form.field "media"
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
                        Form.runOneOfServerSide
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
                    checkinFormParser :
                        Form
                            String
                            { combine : Combined String ( Date, Date ), view : a -> MyView }
                            data
                    checkinFormParser =
                        Form.init
                            (\checkin checkout ->
                                { combine =
                                    Validation.succeed
                                        (\checkinValue checkoutValue ->
                                            Validation.succeed ( checkinValue, checkoutValue )
                                                |> (if Date.toRataDie checkinValue >= Date.toRataDie checkoutValue then
                                                        Validation.withError checkin "Must be before checkout"

                                                    else
                                                        identity
                                                   )
                                        )
                                        |> Validation.andMap checkin
                                        |> Validation.andMap checkout
                                        |> Validation.andThen identity
                                , view =
                                    \_ -> Div
                                }
                            )
                            |> Form.field "checkin"
                                (Field.date { invalid = \_ -> "Invalid" } |> Field.required "Required")
                            |> Form.field "checkout"
                                (Field.date { invalid = \_ -> "Invalid" } |> Field.required "Required")
                in
                [ test "checkin must be before checkout" <|
                    \() ->
                        Form.runOneOfServerSide
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
                        Form.runServerSide
                            (fields
                                [ ( "checkin", "2022-01-03" )
                                , ( "checkout", "2022-01-01" )
                                ]
                            )
                            checkinFormParser
                            |> Expect.equal
                                ( Just ( Date.fromRataDie 738158, Date.fromRataDie 738156 )
                                , Dict.fromList
                                    [ ( "checkin", [ "Must be before checkout" ] )
                                    ]
                                )
                , test "sub-form" <|
                    \() ->
                        Form.runServerSide
                            (fields
                                [ ( "password", "mypassword" )
                                , ( "password-confirmation", "doesnt-match" )
                                ]
                            )
                            (Form.init
                                (\postForm_ ->
                                    { combine =
                                        postForm_.combine ()
                                    , view =
                                        \_ -> ( [], [ Div ] )
                                    }
                                )
                                |> Form.dynamic
                                    (\() ->
                                        Form.init
                                            (\password passwordConfirmation ->
                                                { combine =
                                                    Validation.succeed
                                                        (\passwordValue passwordConfirmationValue ->
                                                            if passwordValue == passwordConfirmationValue then
                                                                Validation.succeed { password = passwordValue }

                                                            else
                                                                passwordConfirmation
                                                                    |> Validation.fail "Must match password"
                                                        )
                                                        |> Validation.andMap password
                                                        |> Validation.andMap passwordConfirmation
                                                        |> Validation.andThen identity
                                                , view = [ Div ]
                                                }
                                            )
                                            |> Form.field "password" (Field.text |> Field.password |> Field.required "Required")
                                            |> Form.field "password-confirmation" (Field.text |> Field.password |> Field.required "Required")
                                    )
                            )
                            |> Expect.equal
                                ( Nothing
                                , Dict.fromList
                                    [ ( "password-confirmation", [ "Must match password" ] )
                                    ]
                                )
                ]
            ]
        , describe "dependent parsing" <|
            let
                linkForm : Form String { combine : Combined String PostAction, view : Form.Context String data -> MyView } data
                linkForm =
                    Form.init
                        (\url ->
                            { combine =
                                Validation.succeed ParsedLink
                                    |> Validation.andMap url
                            , view =
                                \_ -> Div
                            }
                        )
                        |> Form.field "url"
                            (Field.text
                                |> Field.required "Required"
                                |> Field.url
                            )

                postForm : Form String { combine : Combined String PostAction, view : Form.Context String data -> MyView } data
                postForm =
                    Form.init
                        (\title body ->
                            { combine =
                                Validation.succeed
                                    (\titleValue bodyValue ->
                                        { title = titleValue
                                        , body = bodyValue
                                        }
                                    )
                                    |> Validation.andMap title
                                    |> Validation.andMap body
                                    |> Validation.map ParsedPost
                            , view = \_ -> Div
                            }
                        )
                        |> Form.field "title" (Field.text |> Field.required "Required")
                        |> Form.field "body" Field.text

                dependentParser : Form String { combine : Combined String PostAction, view : Form.Context String data -> MyView } data
                dependentParser =
                    Form.init
                        (\kind postForm_ ->
                            { combine =
                                kind
                                    |> Validation.andThen postForm_.combine
                            , view = \_ -> Div
                            }
                        )
                        |> Form.field "kind"
                            (Field.select
                                [ ( "link", Link )
                                , ( "post", Post )
                                ]
                                (\_ -> "Invalid")
                                |> Field.required "Required"
                            )
                        |> Form.dynamic
                            (\parsedKind ->
                                case parsedKind of
                                    Link ->
                                        linkForm

                                    Post ->
                                        postForm
                            )
            in
            [ test "parses link" <|
                \() ->
                    Form.runOneOfServerSide
                        (fields
                            [ ( "kind", "link" )
                            , ( "url", "https://elm-radio.com/episode/wrap-early-unwrap-late" )
                            ]
                        )
                        [ dependentParser ]
                        |> Expect.equal
                            ( Just (ParsedLink "https://elm-radio.com/episode/wrap-early-unwrap-late")
                            , Dict.empty
                            )
            ]
        ]


type PostAction
    = ParsedLink String
    | ParsedPost { title : String, body : Maybe String }


type PostKind
    = Link
    | Post


type Media
    = Book
    | Article
    | Video


type MyView
    = Div


fields : List ( String, String ) -> List ( String, String )
fields list =
    list
