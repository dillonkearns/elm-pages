module QueryParamsTests exposing (all)

import Dict
import Expect
import QueryParams
import Test exposing (describe, test)


all =
    describe "QueryParams"
        [ test "run Url.Parser.Query" <|
            \() ->
                "q=mySearch"
                    |> QueryParams.fromString
                    |> QueryParams.parse (QueryParams.string "q")
                    |> Expect.equal (Ok "mySearch")
        , test "multiple params with same name" <|
            \() ->
                "q=mySearch1&q=mySearch2"
                    |> QueryParams.fromString
                    |> QueryParams.parse (QueryParams.strings "q")
                    |> Expect.equal (Ok [ "mySearch1", "mySearch2" ])
        , test "missing expected key" <|
            \() ->
                "otherKey=notQueryKey"
                    |> QueryParams.fromString
                    |> QueryParams.parse (QueryParams.string "q")
                    |> Expect.equal (Err "Missing key q")
        , test "optional key" <|
            \() ->
                "otherKey=notQueryKey"
                    |> QueryParams.fromString
                    |> QueryParams.parse (QueryParams.optionalString "q")
                    |> Expect.equal (Ok Nothing)
        , test "toDict" <|
            \() ->
                "q=mySearch1&q=mySearch2"
                    |> QueryParams.fromString
                    |> QueryParams.toDict
                    |> Expect.equal
                        (Dict.fromList
                            [ ( "q", [ "mySearch1", "mySearch2" ] )
                            ]
                        )
        , test "oneOf with no parsers" <|
            \() ->
                "q=mySearch1&q=mySearch2"
                    |> QueryParams.fromString
                    |> QueryParams.parse (QueryParams.oneOf [])
                    |> Expect.equal (Err "")
        , test "oneOf with two parsers" <|
            \() ->
                "first=Jane&last=Doe"
                    |> QueryParams.fromString
                    |> QueryParams.parse
                        (QueryParams.oneOf
                            [ QueryParams.string "fullName"
                            , QueryParams.map2
                                (\first last -> first ++ " " ++ last)
                                (QueryParams.string "first")
                                (QueryParams.string "last")
                            ]
                        )
                    |> Expect.equal (Ok "Jane Doe")
        , test "andThen success" <|
            \() ->
                "max=123"
                    |> QueryParams.fromString
                    |> QueryParams.parse
                        (QueryParams.string "max"
                            |> QueryParams.andThen
                                (\value ->
                                    value
                                        |> String.toInt
                                        |> Result.fromMaybe "Expected int"
                                        |> QueryParams.fromResult
                                )
                        )
                    |> Expect.equal (Ok 123)
        , test "andThen failure" <|
            \() ->
                "max=abc"
                    |> QueryParams.fromString
                    |> QueryParams.parse
                        (QueryParams.string "max"
                            |> QueryParams.andThen
                                (\value ->
                                    value
                                        |> String.toInt
                                        |> Result.fromMaybe "Expected int"
                                        |> QueryParams.fromResult
                                )
                        )
                    |> Expect.equal (Err "Expected int")
        ]
