module FormDataTest exposing (all)

import Dict
import Expect
import FormData
import Test exposing (Test, describe, test)


all : Test
all =
    describe "FormData"
        [ test "single field" <|
            \() ->
                "user=dillon"
                    |> FormData.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "user"
                              , ( "dillon", [] )
                              )
                            ]
                        )
        , test "multiple fields" <|
            \() ->
                "custname=Customer+name&custtel=123456&custemail=hello%40example.com&size=medium&topping=bacon&delivery=&comments="
                    |> FormData.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "comments", ( "", [] ) )
                            , ( "custemail", ( "hello@example.com", [] ) )
                            , ( "custname", ( "Customer name", [] ) )
                            , ( "custtel", ( "123456", [] ) )
                            , ( "delivery", ( "", [] ) )
                            , ( "size", ( "medium", [] ) )
                            , ( "topping", ( "bacon", [] ) )
                            ]
                        )
        , test "duplicate empty fields" <|
            \() ->
                "name=&name=&name="
                    |> FormData.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "name", ( "", [ "", "" ] ) )
                            ]
                        )
        , test "duplicate fields" <|
            \() ->
                "name=name1&name=%26name2&name=%22this+is+name+3%22"
                    |> FormData.parse
                    |> Expect.equalDicts
                        (Dict.fromList
                            [ ( "name"
                              , ( "name1", [ "&name2", "\"this is name 3\"" ] )
                              )
                            ]
                        )
        ]
