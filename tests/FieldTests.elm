module FieldTests exposing (all)

import Date
import Expect
import Form.Value as Value
import Pages.Field as Field exposing (Field(..))
import Test exposing (Test, describe, test)


all : List Test
all =
    [ test "options" <|
        \() ->
            (Field.select
                [ ( "link", Link )
                , ( "post", Post )
                ]
                (\_ -> "Invalid")
                |> Field.required "Required"
            )
                |> expect
                    [ ( Just "link", Ok Link )
                    , ( Just "post", Ok Post )
                    , ( Just "unexpected", Err [ "Invalid" ] )
                    ]
    , test "validates optional ints" <|
        \() ->
            Field.int { invalid = \_ -> "Invalid" }
                |> expect
                    [ ( Just "", Ok Nothing )
                    , ( Nothing, Ok Nothing )
                    , ( Just "1", Ok (Just 1) )
                    , ( Just "1.23", Err [ "Invalid" ] )
                    ]
    , test "required int" <|
        \() ->
            Field.int { invalid = \_ -> "Invalid" }
                |> Field.required "Required"
                |> expect
                    [ ( Just "", Err [ "Required" ] )
                    , ( Nothing, Err [ "Required" ] )
                    , ( Just "1", Ok 1 )
                    , ( Just "1.23", Err [ "Invalid" ] )
                    ]
    , test "required int with range" <|
        \() ->
            Field.int { invalid = \_ -> "Invalid" }
                |> Field.required "Required"
                |> Field.withMin (Value.int 100) "Must be at least 100"
                --|> Field.withMax (Value.int 200)
                |> expect
                    [ ( Just "", Err [ "Required" ] )
                    , ( Nothing, Err [ "Required" ] )
                    , ( Just "1", Err [ "Must be at least 100" ] )
                    , ( Just "100", Ok 100 )
                    , ( Just "1.23", Err [ "Invalid" ] )
                    ]
    , test "required float with range" <|
        \() ->
            Field.float { invalid = \_ -> "Invalid" }
                |> Field.required "Required"
                |> Field.withMin (Value.float 100) "Must be at least 100"
                |> Field.withMax (Value.float 200) "Too large"
                |> expect
                    [ ( Just "", Err [ "Required" ] )
                    , ( Nothing, Err [ "Required" ] )
                    , ( Just "1", Err [ "Must be at least 100" ] )
                    , ( Just "100.1", Ok 100.1 )
                    , ( Just "200", Ok 200 )
                    , ( Just "200.1", Err [ "Too large" ] )
                    , ( Just "201", Err [ "Too large" ] )
                    , ( Just "99.9", Err [ "Must be at least 100" ] )
                    ]
    , test "optional text" <|
        \() ->
            Field.text
                |> expect
                    [ ( Just "", Ok Nothing )
                    , ( Nothing, Ok Nothing )
                    , ( Just "Hello", Ok (Just "Hello") )
                    ]
    , test "text with minlength and maxlength" <|
        \() ->
            Field.text
                |> Field.withMinLength 4 "Must be at least 4 characters"
                |> Field.withMaxLength 10 "Must be at most 10 characters"
                |> expect
                    [ ( Just "", Err [ "Must be at least 4 characters" ] )
                    , ( Nothing, Err [ "Must be at least 4 characters" ] )
                    , ( Just "abc", Err [ "Must be at least 4 characters" ] )
                    , ( Just "abcd", Ok (Just "abcd") )
                    , ( Just "abcde", Ok (Just "abcde") )
                    , ( Just "1234567890", Ok (Just "1234567890") )
                    , ( Just "1234567890a", Err [ "Must be at most 10 characters" ] )
                    ]
    , test "required date with range" <|
        \() ->
            Field.date { invalid = \_ -> "Invalid" }
                |> Field.required "Required"
                |> Field.withMin (Value.date (Date.fromRataDie 738156)) "Must be 2022 or later"
                |> Field.withMax (Value.date (Date.fromRataDie 738158)) "Choose an earlier date"
                |> expect
                    [ ( Just "", Err [ "Required" ] )
                    , ( Nothing, Err [ "Required" ] )
                    , ( Just "2021-12-31", Err [ "Must be 2022 or later" ] )
                    , ( Just "2022-01-01", Ok (Date.fromRataDie 738156) )
                    , ( Just "2022-01-02", Ok (Date.fromRataDie 738157) )
                    , ( Just "2022-01-04", Err [ "Choose an earlier date" ] )
                    , ( Just "1.23", Err [ "Invalid" ] )
                    ]
    , test "optional date with range" <|
        \() ->
            Field.date { invalid = \_ -> "Invalid" }
                |> Field.withMin (Value.date (Date.fromRataDie 738156)) "Must be 2022 or later"
                |> Field.withMax (Value.date (Date.fromRataDie 738158)) "Choose an earlier date"
                |> expect
                    [ ( Just "", Ok Nothing )
                    , ( Nothing, Ok Nothing )
                    , ( Just "2021-12-31", Err [ "Must be 2022 or later" ] )
                    , ( Just "2022-01-01", Ok (Just (Date.fromRataDie 738156)) )
                    , ( Just "2022-01-02", Ok (Just (Date.fromRataDie 738157)) )
                    , ( Just "2022-01-04", Err [ "Choose an earlier date" ] )
                    , ( Just "1.23", Err [ "Invalid" ] )
                    ]
    , test "optional date" <|
        \() ->
            Field.date { invalid = \_ -> "Invalid" }
                |> expect
                    [ ( Just "", Ok Nothing )
                    , ( Nothing, Ok Nothing )
                    , ( Just "2022-01-01", Ok (Just (Date.fromRataDie 738156)) )
                    ]
    , test "required date" <|
        \() ->
            Field.date { invalid = \_ -> "Invalid" }
                |> Field.required "Required"
                |> expect
                    [ ( Just "", Err [ "Required" ] )
                    , ( Nothing, Err [ "Required" ] )
                    , ( Just "2022-01-01", Ok (Date.fromRataDie 738156) )
                    ]
    , test "optional time" <|
        \() ->
            Field.time { invalid = \_ -> "Invalid" }
                |> expect
                    [ ( Just "", Ok Nothing )
                    , ( Nothing, Ok Nothing )
                    , ( Just "13:45", Ok (Just { hours = 13, minutes = 45 }) )
                    ]
    ]


expect : List ( Maybe String, Result (List error) parsed ) -> Field error parsed data kind constraints -> Expect.Expectation
expect expectations (Field info _) =
    Expect.all
        (expectations
            |> List.map
                (\( rawInput, expectedOutput ) ->
                    \() ->
                        (case info.decode rawInput of
                            ( Just parsed, [] ) ->
                                Ok parsed

                            ( _, errors ) ->
                                Err errors
                        )
                            |> Expect.equal expectedOutput
                )
        )
        ()


type PostKind
    = Link
    | Post
