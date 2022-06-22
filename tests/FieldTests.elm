module FieldTests exposing (all)

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
