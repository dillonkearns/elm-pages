module CookieTest exposing (all)

import CookieParser
import Dict
import Expect
import Test exposing (Test, describe, test)



-- source: https://github.com/jshttp/cookie/blob/0b519534a5d0bea176f8422aeb93f7d9fce8d683/test/parse.js


all : Test
all =
    describe "Cookie"
        [ test "no special characters or spaces" <|
            \() ->
                "foo=bar"
                    |> CookieParser.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "foo", "bar" )
                            ]
                        )
        , test "no special characters or spaces, numeric value" <|
            \() ->
                "foo=123"
                    |> CookieParser.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "foo", "123" )
                            ]
                        )
        , test "with spaces" <|
            \() ->
                "FOO    = bar;   baz  =   raz"
                    |> CookieParser.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "FOO", "bar" )
                            , ( "baz", "raz" )
                            ]
                        )
        , test "quoted value" <|
            \() ->
                "foo=\"bar=123456789&name=Magic+Mouse\""
                    |> CookieParser.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "foo", "bar=123456789&name=Magic+Mouse" )
                            ]
                        )
        , test "escaped characters" <|
            \() ->
                "email=%20%22%2c%3b%2f"
                    |> CookieParser.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "email", " \",;/" )
                            ]
                        )
        , test "dates" <|
            \() ->
                "priority=true; expires=Wed, 29 Jan 2014 17:43:25 GMT; Path=/"
                    |> CookieParser.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "priority", "true" )
                            , ( "Path", "/" )
                            , ( "expires", "Wed, 29 Jan 2014 17:43:25 GMT" )
                            ]
                        )
        , test "missing value" <|
            \() ->
                "foo; bar=1; fizz= ; buzz=2"
                    |> CookieParser.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "bar", "1" )
                            , ( "fizz", "" )
                            , ( "buzz", "2" )
                            ]
                        )
        ]
