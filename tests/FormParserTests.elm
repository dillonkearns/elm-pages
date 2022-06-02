module FormParserTests exposing (all)

import Dict exposing (Dict)
import Expect
import Pages.Form
import Pages.FormParser as FormParser
import Test exposing (Test, describe, test)


formDecoder : FormParser.Parser String ( String, String )
formDecoder =
    FormParser.map2 Tuple.pair
        (FormParser.required "first" "First is required")
        (FormParser.required "last" "Last is required")


all : Test
all =
    describe "Path"
        [ test "join two segments" <|
            \() ->
                FormParser.run
                    (Dict.fromList
                        [ ( "first"
                          , { value = ""
                            , status = Pages.Form.NotVisited
                            }
                          )
                        , ( "last"
                          , { value = ""
                            , status = Pages.Form.NotVisited
                            }
                          )
                        ]
                    )
                    formDecoder
                    |> Expect.equal
                        ( Just ( "", "" )
                        , Dict.fromList
                            [ ( "first", [ "First is required" ] )
                            , ( "last", [ "Last is required" ] )
                            ]
                        )
        ]
