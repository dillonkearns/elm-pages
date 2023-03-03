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
    | SetQuantity ( Uuid, Int )


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
                Form.runOneOfServerSide
                    (fields
                        [ ( "password", "mypassword" )
                        , ( "password-confirmation", "mypassword" )
                        ]
                    )
                    (passwordConfirmationParser |> Form.initCombined identity)
                    |> Expect.equal
                        ( Just { password = "mypassword" }
                        , Dict.empty
                        )
        , test "non-matching password" <|
            \() ->
                Form.runOneOfServerSide
                    (fields
                        [ ( "password", "mypassword" )
                        , ( "password-confirmation", "doesnt-match-password" )
                        ]
                    )
                    (passwordConfirmationParser |> Form.initCombined identity)
                    |> Expect.equal
                        ( Just { password = "mypassword" }
                        , Dict.fromList [ ( "password-confirmation", [ "Must match password" ] ) ]
                        )
        , describe "oneOf" <|
            let
                oneOfParsers : Form.ServerForms String Action
                oneOfParsers =
                    Form.initCombined SetQuantity
                        (Form.init
                            (\_ uuid quantity ->
                                { combine =
                                    Validation.succeed Tuple.pair
                                        |> Validation.andMap (uuid |> Validation.map Uuid)
                                        |> Validation.andMap quantity
                                , view =
                                    \_ -> Div
                                }
                            )
                            |> Form.hiddenField "kind" (Field.exactValue "setQuantity" "Expected setQuantity")
                            |> Form.hiddenField "uuid" (Field.text |> Field.required "Required")
                            |> Form.field "quantity" (Field.int { invalid = \_ -> "Expected int" } |> Field.required "Required")
                        )
                        |> Form.combine (\() -> Signout)
                            (Form.init
                                (\_ ->
                                    { combine = Validation.succeed ()
                                    , view = \_ -> Div
                                    }
                                )
                                |> Form.hiddenField "kind" (Field.exactValue "signout" "Expected signout")
                            )
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
                            ( Just (SetQuantity ( Uuid "123", 1 ))
                            , Dict.empty
                            )
            , test "3rd" <|
                \() ->
                    Form.runOneOfServerSide
                        (fields
                            [ ( "kind", "toggle-all" )
                            , ( "toggleTo", "" )
                            ]
                        )
                        todoForm
                        |> Expect.equal
                            ( Just (CheckAll False)
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
                        Form.init
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
                in
                [ test "example" <|
                    \() ->
                        Form.runOneOfServerSide
                            (fields
                                [ ( "media", "book" )
                                ]
                            )
                            (selectParser |> Form.initCombined identity)
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
                            msg
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
                            (checkinFormParser |> Form.initCombined identity)
                            |> Expect.equal
                                ( Just ( Date.fromRataDie 738156, Date.fromRataDie 738158 )
                                , Dict.empty
                                )
                , test "checkout is invalid because before checkin" <|
                    \() ->
                        Form.runOneOfServerSide
                            (fields
                                [ ( "checkin", "2022-01-03" )
                                , ( "checkout", "2022-01-01" )
                                ]
                            )
                            (checkinFormParser |> Form.initCombined identity)
                            |> Expect.equal
                                ( Just ( Date.fromRataDie 738158, Date.fromRataDie 738156 )
                                , Dict.fromList
                                    [ ( "checkin", [ "Must be before checkout" ] )
                                    ]
                                )
                , test "sub-form" <|
                    \() ->
                        Form.runOneOfServerSide
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
                                |> Form.initCombined identity
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
                linkForm : Form String { combine : Combined String PostAction, view : Form.Context String data -> MyView } data msg
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

                postForm : Form String { combine : Combined String PostAction, view : Form.Context String data -> MyView } data msg
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

                dependentParser : Form String { combine : Combined String PostAction, view : Form.Context String data -> MyView } data msg
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
                        (dependentParser |> Form.initCombined identity)
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


todoForm : Form.ServerForms String TodoAction
todoForm =
    editItemForm
        |> Form.initCombined UpdateEntry
        |> Form.combine Add newItemForm
        |> Form.combine Check completeItemForm
        |> Form.combine Delete deleteItemForm
        |> Form.combine (\_ -> DeleteComplete) clearCompletedForm
        |> Form.combine CheckAll toggleAllForm


type TodoAction
    = UpdateEntry ( String, String )
    | Add String
    | Delete String
    | DeleteComplete
    | Check ( Bool, String )
    | CheckAll Bool


editItemForm : Form.HtmlForm String ( String, String ) input msg
editItemForm =
    Form.init
        (\itemId description ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap itemId
                    |> Validation.andMap description
            , view = \_ -> []
            }
        )
        |> Form.hiddenField "itemId"
            (Field.text
                |> Field.required "Must be present"
            )
        |> Form.field "description"
            (Field.text
                |> Field.required "Must be present"
            )
        |> Form.hiddenKind ( "kind", "edit-item" ) "Expected kind"


newItemForm : Form.HtmlForm String String input msg
newItemForm =
    Form.init
        (\description ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap description
            , view = \_ -> []
            }
        )
        |> Form.field "description" (Field.text |> Field.required "Must be present")
        |> Form.hiddenKind ( "kind", "new-item" ) "Expected kind"


completeItemForm : Form.HtmlForm String ( Bool, String ) input msg
completeItemForm =
    Form.init
        (\todoId complete ->
            { combine =
                Validation.succeed Tuple.pair
                    |> Validation.andMap complete
                    |> Validation.andMap todoId
            , view = \_ -> []
            }
        )
        |> Form.hiddenField "todoId"
            (Field.text
                |> Field.required "Must be present"
            )
        |> Form.hiddenField "complete"
            Field.checkbox
        |> Form.hiddenKind ( "kind", "complete" ) "Expected kind"


deleteItemForm : Form.HtmlForm String String input msg
deleteItemForm =
    Form.init
        (\todoId ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap todoId
            , view = \_ -> []
            }
        )
        |> Form.hiddenField "todoId"
            (Field.text
                |> Field.required "Must be present"
             --|> Field.withInitialValue (.id >> Form.Value.string)
            )
        |> Form.hiddenKind ( "kind", "delete" ) "Expected kind"


clearCompletedForm : Form.HtmlForm String () { entriesCompleted : Int } msg
clearCompletedForm =
    Form.init
        { combine = Validation.succeed ()
        , view = \_ -> []
        }
        |> Form.hiddenKind ( "kind", "clear-completed" ) "Expected kind"


toggleAllForm : Form.HtmlForm String Bool input msg
toggleAllForm =
    Form.init
        (\toggleTo ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap toggleTo
            , view = \_ -> []
            }
        )
        |> Form.hiddenField "toggleTo" Field.checkbox
        |> Form.hiddenKind ( "kind", "toggle-all" ) "Expected kind"
