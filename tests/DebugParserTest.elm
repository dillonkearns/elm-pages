module DebugParserTest exposing (suite)

import Expect
import Test exposing (..)
import Test.PagesProgram.DebugParser as DebugParser exposing (ElmValue(..))


suite : Test
suite =
    describe "DebugParser"
        [ describe "primitives"
            [ test "int" <|
                \() ->
                    DebugParser.parse "42"
                        |> Expect.equal (Ok (ElmInt 42))
            , test "negative int" <|
                \() ->
                    DebugParser.parse "-7"
                        |> Expect.equal (Ok (ElmInt -7))
            , test "float" <|
                \() ->
                    DebugParser.parse "3.14"
                        |> Expect.equal (Ok (ElmFloat 3.14))
            , test "string" <|
                \() ->
                    DebugParser.parse "\"hello world\""
                        |> Expect.equal (Ok (ElmString "hello world"))
            , test "string with escaped quote" <|
                \() ->
                    DebugParser.parse "\"he said \\\"hi\\\"\""
                        |> Expect.equal (Ok (ElmString "he said \"hi\""))
            , test "char" <|
                \() ->
                    DebugParser.parse "'a'"
                        |> Expect.equal (Ok (ElmChar 'a'))
            , test "True" <|
                \() ->
                    DebugParser.parse "True"
                        |> Expect.equal (Ok (ElmBool True))
            , test "False" <|
                \() ->
                    DebugParser.parse "False"
                        |> Expect.equal (Ok (ElmBool False))
            , test "unit" <|
                \() ->
                    DebugParser.parse "()"
                        |> Expect.equal (Ok ElmUnit)
            , test "internals" <|
                \() ->
                    DebugParser.parse "<internals>"
                        |> Expect.equal (Ok (ElmInternals "internals"))
            , test "function" <|
                \() ->
                    DebugParser.parse "<function>"
                        |> Expect.equal (Ok (ElmInternals "function"))
            ]
        , describe "collections"
            [ test "empty list" <|
                \() ->
                    DebugParser.parse "[]"
                        |> Expect.equal (Ok (ElmList []))
            , test "list of ints" <|
                \() ->
                    DebugParser.parse "[1,2,3]"
                        |> Expect.equal (Ok (ElmList [ ElmInt 1, ElmInt 2, ElmInt 3 ]))
            , test "list with spaces" <|
                \() ->
                    DebugParser.parse "[1, 2, 3]"
                        |> Expect.equal (Ok (ElmList [ ElmInt 1, ElmInt 2, ElmInt 3 ]))
            , test "list of strings" <|
                \() ->
                    DebugParser.parse "[\"Elm\",\"elm-pages\"]"
                        |> Expect.equal (Ok (ElmList [ ElmString "Elm", ElmString "elm-pages" ]))
            , test "tuple pair" <|
                \() ->
                    DebugParser.parse "(1,\"a\")"
                        |> Expect.equal (Ok (ElmTuple [ ElmInt 1, ElmString "a" ]))
            , test "tuple triple" <|
                \() ->
                    DebugParser.parse "(1,2,3)"
                        |> Expect.equal (Ok (ElmTuple [ ElmInt 1, ElmInt 2, ElmInt 3 ]))
            , test "parenthesized value (not tuple)" <|
                \() ->
                    DebugParser.parse "(42)"
                        |> Expect.equal (Ok (ElmInt 42))
            ]
        , describe "records"
            [ test "empty record" <|
                \() ->
                    DebugParser.parse "{}"
                        |> Expect.equal (Ok (ElmRecord []))
            , test "simple record" <|
                \() ->
                    DebugParser.parse "{ count = 0 }"
                        |> Expect.equal (Ok (ElmRecord [ ( "count", ElmInt 0 ) ]))
            , test "multi-field record" <|
                \() ->
                    DebugParser.parse "{ name = \"Alice\", age = 30 }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "name", ElmString "Alice" )
                                    , ( "age", ElmInt 30 )
                                    ]
                                )
                            )
            , test "record with list field" <|
                \() ->
                    DebugParser.parse "{ search = \"\", items = [\"Elm\",\"elm-pages\"] }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "search", ElmString "" )
                                    , ( "items", ElmList [ ElmString "Elm", ElmString "elm-pages" ] )
                                    ]
                                )
                            )
            ]
        , describe "custom types"
            [ test "Nothing" <|
                \() ->
                    DebugParser.parse "Nothing"
                        |> Expect.equal (Ok (ElmCustom "Nothing" []))
            , test "Just with int" <|
                \() ->
                    DebugParser.parse "Just 42"
                        |> Expect.equal (Ok (ElmCustom "Just" [ ElmInt 42 ]))
            , test "Just with string" <|
                \() ->
                    DebugParser.parse "Just \"hello\""
                        |> Expect.equal (Ok (ElmCustom "Just" [ ElmString "hello" ]))
            , test "nested Just" <|
                \() ->
                    DebugParser.parse "Just (Just 42)"
                        |> Expect.equal (Ok (ElmCustom "Just" [ ElmCustom "Just" [ ElmInt 42 ] ]))
            , test "Err with string" <|
                \() ->
                    DebugParser.parse "Err \"not found\""
                        |> Expect.equal (Ok (ElmCustom "Err" [ ElmString "not found" ]))
            , test "multi-arg constructor" <|
                \() ->
                    DebugParser.parse "Pair 1 \"hello\""
                        |> Expect.equal (Ok (ElmCustom "Pair" [ ElmInt 1, ElmString "hello" ]))
            ]
        , describe "nested structures"
            [ test "record with custom type value" <|
                \() ->
                    DebugParser.parse "{ status = Just 42 }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "status", ElmCustom "Just" [ ElmInt 42 ] ) ]
                                )
                            )
            , test "record with Nothing value" <|
                \() ->
                    DebugParser.parse "{ value = Nothing }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "value", ElmCustom "Nothing" [] ) ]
                                )
                            )
            , test "record with nested record" <|
                \() ->
                    DebugParser.parse "{ outer = { inner = 1 } }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "outer", ElmRecord [ ( "inner", ElmInt 1 ) ] ) ]
                                )
                            )
            , test "list in custom type" <|
                \() ->
                    DebugParser.parse "Got [1,2,3]"
                        |> Expect.equal
                            (Ok
                                (ElmCustom "Got"
                                    [ ElmList [ ElmInt 1, ElmInt 2, ElmInt 3 ] ]
                                )
                            )
            , test "custom type with record arg" <|
                \() ->
                    DebugParser.parse "User { name = \"Alice\" }"
                        |> Expect.equal
                            (Ok
                                (ElmCustom "User"
                                    [ ElmRecord [ ( "name", ElmString "Alice" ) ] ]
                                )
                            )
            , test "multiple records fields with custom types" <|
                \() ->
                    DebugParser.parse "{ a = Just 1, b = Nothing }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "a", ElmCustom "Just" [ ElmInt 1 ] )
                                    , ( "b", ElmCustom "Nothing" [] )
                                    ]
                                )
                            )
            ]
        , describe "Dict and Set"
            [ test "empty Dict" <|
                \() ->
                    DebugParser.parse "Dict.fromList []"
                        |> Expect.equal (Ok (ElmDict []))
            , test "Dict with entries" <|
                \() ->
                    DebugParser.parse "Dict.fromList [(\"a\",1),(\"b\",2)]"
                        |> Expect.equal
                            (Ok
                                (ElmDict
                                    [ ( ElmString "a", ElmInt 1 )
                                    , ( ElmString "b", ElmInt 2 )
                                    ]
                                )
                            )
            , test "empty Set" <|
                \() ->
                    DebugParser.parse "Set.fromList []"
                        |> Expect.equal (Ok (ElmSet []))
            , test "Set with items" <|
                \() ->
                    DebugParser.parse "Set.fromList [1,2,3]"
                        |> Expect.equal (Ok (ElmSet [ ElmInt 1, ElmInt 2, ElmInt 3 ]))
            ]
        ]
