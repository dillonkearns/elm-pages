module DebugParserTest exposing (suite)

import Expect
import Test exposing (..)
import Test.PagesProgram.DebugParser as DebugParser exposing (ElmValue(..))


suite : Test
suite =
    describe "DebugParser"
        [ describe "primitives"
            [ test "int" <|
                \_ ->
                    DebugParser.parse "42"
                        |> Expect.equal (Ok (ElmInt 42))
            , test "negative int" <|
                \_ ->
                    DebugParser.parse "-7"
                        |> Expect.equal (Ok (ElmInt -7))
            , test "float" <|
                \_ ->
                    DebugParser.parse "3.14"
                        |> Expect.equal (Ok (ElmFloat 3.14))
            , test "string" <|
                \_ ->
                    DebugParser.parse "\"hello world\""
                        |> Expect.equal (Ok (ElmString "hello world"))
            , test "string with escaped quote" <|
                \_ ->
                    DebugParser.parse "\"he said \\\"hi\\\"\""
                        |> Expect.equal (Ok (ElmString "he said \"hi\""))
            , test "char" <|
                \_ ->
                    DebugParser.parse "'a'"
                        |> Expect.equal (Ok (ElmChar 'a'))
            , test "True" <|
                \_ ->
                    DebugParser.parse "True"
                        |> Expect.equal (Ok (ElmBool True))
            , test "False" <|
                \_ ->
                    DebugParser.parse "False"
                        |> Expect.equal (Ok (ElmBool False))
            , test "unit" <|
                \_ ->
                    DebugParser.parse "()"
                        |> Expect.equal (Ok ElmUnit)
            , test "internals" <|
                \_ ->
                    DebugParser.parse "<internals>"
                        |> Expect.equal (Ok (ElmInternals "internals"))
            , test "function" <|
                \_ ->
                    DebugParser.parse "<function>"
                        |> Expect.equal (Ok (ElmInternals "function"))
            ]
        , describe "collections"
            [ test "empty list" <|
                \_ ->
                    DebugParser.parse "[]"
                        |> Expect.equal (Ok (ElmList []))
            , test "list of ints" <|
                \_ ->
                    DebugParser.parse "[1,2,3]"
                        |> Expect.equal (Ok (ElmList [ ElmInt 1, ElmInt 2, ElmInt 3 ]))
            , test "list with spaces" <|
                \_ ->
                    DebugParser.parse "[1, 2, 3]"
                        |> Expect.equal (Ok (ElmList [ ElmInt 1, ElmInt 2, ElmInt 3 ]))
            , test "list of strings" <|
                \_ ->
                    DebugParser.parse "[\"Elm\",\"elm-pages\"]"
                        |> Expect.equal (Ok (ElmList [ ElmString "Elm", ElmString "elm-pages" ]))
            , test "tuple pair" <|
                \_ ->
                    DebugParser.parse "(1,\"a\")"
                        |> Expect.equal (Ok (ElmTuple [ ElmInt 1, ElmString "a" ]))
            , test "tuple triple" <|
                \_ ->
                    DebugParser.parse "(1,2,3)"
                        |> Expect.equal (Ok (ElmTuple [ ElmInt 1, ElmInt 2, ElmInt 3 ]))
            , test "parenthesized value (not tuple)" <|
                \_ ->
                    DebugParser.parse "(42)"
                        |> Expect.equal (Ok (ElmInt 42))
            ]
        , describe "records"
            [ test "empty record" <|
                \_ ->
                    DebugParser.parse "{}"
                        |> Expect.equal (Ok (ElmRecord []))
            , test "simple record" <|
                \_ ->
                    DebugParser.parse "{ count = 0 }"
                        |> Expect.equal (Ok (ElmRecord [ ( "count", ElmInt 0 ) ]))
            , test "multi-field record" <|
                \_ ->
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
                \_ ->
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
                \_ ->
                    DebugParser.parse "Nothing"
                        |> Expect.equal (Ok (ElmCustom "Nothing" []))
            , test "Just with int" <|
                \_ ->
                    DebugParser.parse "Just 42"
                        |> Expect.equal (Ok (ElmCustom "Just" [ ElmInt 42 ]))
            , test "Just with string" <|
                \_ ->
                    DebugParser.parse "Just \"hello\""
                        |> Expect.equal (Ok (ElmCustom "Just" [ ElmString "hello" ]))
            , test "nested Just" <|
                \_ ->
                    DebugParser.parse "Just (Just 42)"
                        |> Expect.equal (Ok (ElmCustom "Just" [ ElmCustom "Just" [ ElmInt 42 ] ]))
            , test "Err with string" <|
                \_ ->
                    DebugParser.parse "Err \"not found\""
                        |> Expect.equal (Ok (ElmCustom "Err" [ ElmString "not found" ]))
            , test "multi-arg constructor" <|
                \_ ->
                    DebugParser.parse "Pair 1 \"hello\""
                        |> Expect.equal (Ok (ElmCustom "Pair" [ ElmInt 1, ElmString "hello" ]))
            ]
        , describe "nested structures"
            [ test "record with custom type value" <|
                \_ ->
                    DebugParser.parse "{ status = Just 42 }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "status", ElmCustom "Just" [ ElmInt 42 ] ) ]
                                )
                            )
            , test "record with Nothing value" <|
                \_ ->
                    DebugParser.parse "{ value = Nothing }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "value", ElmCustom "Nothing" [] ) ]
                                )
                            )
            , test "record with nested record" <|
                \_ ->
                    DebugParser.parse "{ outer = { inner = 1 } }"
                        |> Expect.equal
                            (Ok
                                (ElmRecord
                                    [ ( "outer", ElmRecord [ ( "inner", ElmInt 1 ) ] ) ]
                                )
                            )
            , test "list in custom type" <|
                \_ ->
                    DebugParser.parse "Got [1,2,3]"
                        |> Expect.equal
                            (Ok
                                (ElmCustom "Got"
                                    [ ElmList [ ElmInt 1, ElmInt 2, ElmInt 3 ] ]
                                )
                            )
            , test "custom type with record arg" <|
                \_ ->
                    DebugParser.parse "User { name = \"Alice\" }"
                        |> Expect.equal
                            (Ok
                                (ElmCustom "User"
                                    [ ElmRecord [ ( "name", ElmString "Alice" ) ] ]
                                )
                            )
            , test "multiple records fields with custom types" <|
                \_ ->
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
                \_ ->
                    DebugParser.parse "Dict.fromList []"
                        |> Expect.equal (Ok (ElmDict []))
            , test "Dict with entries" <|
                \_ ->
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
                \_ ->
                    DebugParser.parse "Set.fromList []"
                        |> Expect.equal (Ok (ElmSet []))
            , test "Set with items" <|
                \_ ->
                    DebugParser.parse "Set.fromList [1,2,3]"
                        |> Expect.equal (Ok (ElmSet [ ElmInt 1, ElmInt 2, ElmInt 3 ]))
            ]
        ]
