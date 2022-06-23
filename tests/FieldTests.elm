module FieldTests exposing (all)

import Date
import Expect
import Pages.Field as Field exposing (Field(..))
import Test exposing (Test, describe, test)


all : Test
all =
    describe "FieldTests"
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
        ]


expect : List ( Maybe String, Result (List error) parsed ) -> Field error parsed data kind constraints -> Expect.Expectation
expect expectations (Field info kind) =
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
