module ElmToHtmlTests exposing (..)

import ElmHtml.InternalTypes
import ElmHtml.ToString
import Expect
import Json.Decode
import Test exposing (describe, test)


all =
    describe "ElmToHtml"
        [ test "lazy" <|
            \() ->
                {-
                   -                    "$": 0,
                   -                    "a": "<script></script> is unsafe in JSON unless it is escaped properly.\n"

                -}
                """
{"$":5,"l":[null,{"$":"#0"}]}
"""
                    |> Json.Decode.decodeString (ElmHtml.InternalTypes.decodeElmHtml (\_ _ -> Json.Decode.succeed ()))
                    |> Result.map ElmHtml.ToString.nodeToString
                    |> Expect.equal (Ok "HELLO")
        , test "no lazys" <|
            \() ->
                """
{"$":0,"a":"HELLO"}
"""
                    |> Json.Decode.decodeString (ElmHtml.InternalTypes.decodeElmHtml (\_ _ -> Json.Decode.succeed ()))
                    |> Result.map ElmHtml.ToString.nodeToString
                    |> Expect.equal (Ok "HELLO")
        ]
