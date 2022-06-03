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


type Uuid
    = Uuid String


type Action
    = Signout
    | SetQuantity Uuid Int


all : Test
all =
    describe "Form Parser"
        [ test "error for missing required fields" <|
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
        , test "parse into custom type" <|
            \() ->
                FormParser.run
                    (Dict.fromList
                        [ ( "kind"
                          , { value = "signout"
                            , status = Pages.Form.NotVisited
                            }
                          )
                        ]
                    )
                    (FormParser.required "kind" "Kind is required"
                        |> FormParser.andThen
                            (\kind ->
                                if kind == "signout" then
                                    FormParser.succeed Signout

                                else if kind == "add" then
                                    FormParser.map2 SetQuantity
                                        (FormParser.required "itemId" "First is required" |> FormParser.map Uuid)
                                        (FormParser.int "setQuantity" "Expected setQuantity to be an integer")

                                else
                                    FormParser.fail "Error"
                            )
                    )
                    |> Expect.equal
                        ( Just Signout
                        , Dict.empty
                        )
        , test "parse into custom type with int" <|
            \() ->
                FormParser.run
                    (fields
                        [ ( "kind", "add" )
                        , ( "itemId", "123" )
                        , ( "setQuantity", "1" )
                        ]
                    )
                    (FormParser.required "kind" "Kind is required"
                        |> FormParser.andThen
                            (\kind ->
                                if kind == "signout" then
                                    FormParser.succeed Signout

                                else if kind == "add" then
                                    FormParser.map2 SetQuantity
                                        (FormParser.required "itemId" "First is required" |> FormParser.map Uuid)
                                        -- TODO what's the best way to combine together int and required? Should it be `requiredInt`, or `Form.required |> Form.int`?
                                        (FormParser.int "setQuantity" "Expected setQuantity to be an integer")

                                else
                                    FormParser.fail "Error"
                            )
                    )
                    |> Expect.equal
                        ( Just (SetQuantity (Uuid "123") 1)
                        , Dict.empty
                        )
        ]


field : String -> String -> ( String, Pages.Form.FieldState )
field name value =
    ( name
    , { value = value
      , status = Pages.Form.NotVisited
      }
    )


fields : List ( String, String ) -> Dict String Pages.Form.FieldState
fields list =
    list
        |> List.map (\( name, value ) -> field name value)
        |> Dict.fromList
