module FormTests exposing (all)

import Date exposing (Date)
import Dict exposing (Dict)
import Expect
import Pages.Field as Field
import Pages.Form as Form exposing (Form)
import Pages.FormState
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
                        if password.value /= passwordConfirmation.value then
                            ( Nothing
                            , Dict.fromList
                                [ ( passwordConfirmation.name, [ "Must match password" ] )
                                ]
                            )

                        else
                            Form.ok { password = password.value }
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
                        (\_ -> Form.ok Signout)
                        (\fieldErrors -> Div)
                        |> Form.hiddenField "kind" (Field.exactValue "signout" "Expected signout")
                    , Form.init
                        (\_ uuid quantity ->
                            SetQuantity (Uuid uuid.value) quantity.value
                                |> Form.ok
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
                                    |> Form.ok
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
                                if Date.toRataDie checkin.value >= Date.toRataDie checkout.value then
                                    ( Just ( checkin.value, checkout.value )
                                    , Dict.fromList
                                        [ ( "checkin", [ "Must be before checkout" ] )
                                        ]
                                    )

                                else
                                    Form.ok ( checkin.value, checkout.value )
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
                ]
            ]
        , describe "dependent parsing" <|
            let
                --checkinFormParser : Form.HtmlForm String ( Date, Date ) data msg
                --dependentParser : Form.Form String ( Maybe ( Date, Date ), Dict String (List String) ) data (Form.Context String -> MyView)
                linkForm : Form.Form String ( Maybe PostAction, Form.FieldErrors error ) data (Form.Context String data -> MyView)
                linkForm =
                    Form.init
                        (\url ->
                            Form.ok (ParsedLink url.value)
                        )
                        (\fieldErrors url -> Div)
                        |> Form.field "url"
                            (Field.text
                                |> Field.required "Required"
                                |> Field.url
                            )

                postForm : Form.Form String ( Maybe PostAction, Form.FieldErrors error ) data (Form.Context String data -> MyView)
                postForm =
                    Form.init
                        (\title body ->
                            Form.ok
                                (ParsedPost
                                    { title = title.value
                                    , body = body.value
                                    }
                                )
                        )
                        (\fieldErrors title body -> Div)
                        |> Form.field "title" (Field.text |> Field.required "Required")
                        |> Form.field "body" Field.text

                dependentParser : Form.Form String ( Maybe PostAction, Form.FieldErrors String ) data (Form.Context String data -> MyView)
                dependentParser =
                    Form.init
                        (\kind postForm_ ->
                            postForm_ kind.value
                                |> Form.andThen identity
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
