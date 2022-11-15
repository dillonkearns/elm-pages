module HeadTests exposing (suite)

import Expect
import Head
import Json.Decode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "strips loading/pre-loading directives"
        [ test "strips script" <|
            \() ->
                Head.nonLoadingNode "script"
                    [ ( "src", Head.raw "/script.js" )
                    ]
                    |> expectStripped
        , test "strips script with different casing" <|
            \() ->
                Head.nonLoadingNode "scripT"
                    [ ( "src", Head.raw "/script.js" )
                    ]
                    |> expectStripped
        , test "link preload is stripped" <|
            \() ->
                Head.nonLoadingNode "link"
                    [ ( "rel", Head.raw "preload" )
                    ]
                    |> expectStripped
        , test "link modulepreload is stripped" <|
            \() ->
                Head.nonLoadingNode "link"
                    [ ( "rel", Head.raw "modulepreload" )
                    ]
                    |> expectStripped
        , test "link stylesheet is stripped" <|
            \() ->
                Head.nonLoadingNode "link"
                    [ ( "rel", Head.raw "stylesheet" )
                    , ( "src", Head.raw "/style.css" )
                    ]
                    |> expectStripped
        , test "preserves non-loading link tags" <|
            \() ->
                Head.nonLoadingNode "link"
                    [ ( "rel", Head.raw "me" )
                    , ( "href", Head.raw "mysite.com" )
                    ]
                    |> expectPreserved
        ]


expectStripped : Head.Tag -> Expect.Expectation
expectStripped actual =
    actual
        |> Head.toJson "" ""
        |> Json.Decode.decodeValue (Json.Decode.field "type" Json.Decode.string)
        |> Expect.equal (Ok "stripped")


expectPreserved : Head.Tag -> Expect.Expectation
expectPreserved actual =
    actual
        |> Head.toJson "" ""
        |> Json.Decode.decodeValue (Json.Decode.field "type" Json.Decode.string)
        |> Expect.notEqual (Ok "stripped")
