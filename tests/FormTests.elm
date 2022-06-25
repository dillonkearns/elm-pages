module FormTests exposing (all)

import Date exposing (Date)
import Dict exposing (Dict)
import Expect
import Pages.Field as Field
import Pages.Form as Form exposing (Form)
import Pages.FormState
import Test exposing (Test, describe, test)
import Validation exposing (Validation)


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
                        Validation.succeed
                            (\passwordValue passwordConfirmationValue ->
                                if passwordValue == passwordConfirmationValue then
                                    Validation.succeed { password = passwordValue }

                                else
                                    Validation.fail passwordConfirmation.name "Must match password"
                            )
                            |> Validation.withField password
                            |> Validation.withField passwordConfirmation
                            |> Validation.andThen identity
                    )
                    (\fieldErrors password passwordConfirmation -> Div)
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
                        ( Nothing
                        , Dict.fromList [ ( "password-confirmation", [ "Must match password" ] ) ]
                        )
        , describe "oneOf" <|
            let
                oneOfParsers =
                    [ Form.init
                        (\_ -> Validation.succeed Signout)
                        (\fieldErrors -> Div)
                        |> Form.hiddenField "kind" (Field.exactValue "signout" "Expected signout")
                    , Form.init
                        (\_ uuid quantity ->
                            Validation.succeed SetQuantity
                                |> Validation.andMap (uuid.value |> Validation.map Uuid)
                                |> Validation.withField quantity
                        )
                        (\fieldErrors quantity -> Div)
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
                                media.value
                            )
                            (\fieldErrors media -> Div)
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
                    --checkinFormParser : Form.HtmlForm String ( Date, Date ) data msg
                    checkinFormParser : Form.Form String ( Maybe ( Date, Date ), Dict String (List String) ) data (Form.Context String data -> MyView)
                    checkinFormParser =
                        Form.init
                            (\checkin checkout ->
                                Validation.succeed
                                    (\checkinValue checkoutValue ->
                                        if Date.toRataDie checkinValue >= Date.toRataDie checkoutValue then
                                            Validation.fail checkin.name "Must be before checkout"

                                        else
                                            Validation.succeed ( checkinValue, checkoutValue )
                                    )
                                    |> Validation.withField checkin
                                    |> Validation.withField checkout
                                    |> Validation.andThen identity
                            )
                            (\fieldErrors checkin checkout -> Div)
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
                                  --( Just (Date.fromRataDie 738158)
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
                                    postForm_ ()
                                        -- TODO @@@@ remove Tuple.first
                                        |> Tuple.first
                                )
                                (\formState postForm_ -> ( [], [ Div ] ))
                                |> Form.dynamic
                                    (\() ->
                                        Form.init
                                            (\password passwordConfirmation ->
                                                if password.value == passwordConfirmation.value then
                                                    Form.ok password.value

                                                else
                                                    --Form.ok password.value|>
                                                    Form.fail passwordConfirmation "Must match password"
                                            )
                                            (\formState password passwordConfirmation -> [ Div ])
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
                linkForm : Form String (Validation String PostAction) data (Form.Context String data -> MyView)
                linkForm =
                    Form.init
                        (\url ->
                            Validation.succeed ParsedLink
                                |> Validation.withField url
                        )
                        (\fieldErrors url -> Div)
                        |> Form.field "url"
                            (Field.text
                                |> Field.required "Required"
                                |> Field.url
                            )

                postForm : Form String (Validation String PostAction) data (Form.Context String data -> MyView)
                postForm =
                    Form.init
                        (\title body ->
                            Validation.succeed
                                (\titleValue bodyValue ->
                                    { title = titleValue
                                    , body = bodyValue
                                    }
                                )
                                |> Validation.withField title
                                |> Validation.withField body
                                |> Validation.map ParsedPost
                        )
                        (\fieldErrors title body -> Div)
                        |> Form.field "title" (Field.text |> Field.required "Required")
                        |> Form.field "body" Field.text

                dependentParser : Form String (Validation String PostAction) data (Form.Context String data -> MyView)
                dependentParser =
                    Form.init
                        (\kind postForm_ ->
                            kind.value
                                |> Validation.andThen
                                    (\kindValue ->
                                        postForm_ kindValue
                                            -- TODO @@@@@ remove Tuple.first
                                            |> Tuple.first
                                    )
                        )
                        (\fieldErrors kind postForm_ ->
                            Div
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


field : String -> String -> ( String, Pages.FormState.FieldState )
field name value =
    ( name
    , { value = value
      , status = Pages.FormState.NotVisited
      }
    )


fields : List ( String, String ) -> List ( String, String )
fields list =
    list
