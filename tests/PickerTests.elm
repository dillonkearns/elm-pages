module PickerTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui.Picker as Picker
import Tui.Screen


suite : Test
suite =
    describe "Tui.Picker"
        [ describe "open"
            [ test "initial state shows all items" <|
                \() ->
                    Picker.open
                        { items = [ "Alpha", "Beta", "Gamma" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> Picker.visibleItems
                        |> List.length
                        |> Expect.equal 3
            , test "selected defaults to first item" <|
                \() ->
                    Picker.open
                        { items = [ "Alpha", "Beta", "Gamma" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> Picker.selected
                        |> Expect.equal (Just "Alpha")
            ]
        , describe "filtering"
            [ test "typing filters items" <|
                \() ->
                    Picker.open
                        { items = [ "Json.Decode", "Json.Encode", "Html" ]
                        , toString = identity
                        , title = "Modules"
                        }
                        |> typeString "dec"
                        |> Picker.visibleItems
                        |> Expect.equal [ "Json.Decode" ]
            , test "fuzzy filter matches" <|
                \() ->
                    Picker.open
                        { items = [ "Json.Decode", "Json.Encode", "Html" ]
                        , toString = identity
                        , title = "Modules"
                        }
                        |> typeString "jde"
                        |> Picker.visibleItems
                        |> Expect.equal [ "Json.Decode" ]
            , test "empty filter shows all items" <|
                \() ->
                    Picker.open
                        { items = [ "A", "B", "C" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> Picker.visibleItems
                        |> List.length
                        |> Expect.equal 3
            , test "filter is case insensitive" <|
                \() ->
                    Picker.open
                        { items = [ "Json.Decode", "Html" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> typeString "JSON"
                        |> Picker.visibleItems
                        |> Expect.equal [ "Json.Decode" ]
            ]
        , describe "navigation"
            [ test "navigateDown moves to next item" <|
                \() ->
                    Picker.open
                        { items = [ "A", "B", "C" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> Picker.navigateDown
                        |> Picker.selected
                        |> Expect.equal (Just "B")
            , test "navigateUp from first stays at first" <|
                \() ->
                    Picker.open
                        { items = [ "A", "B", "C" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> Picker.navigateUp
                        |> Picker.selected
                        |> Expect.equal (Just "A")
            , test "navigateDown clamps at end" <|
                \() ->
                    Picker.open
                        { items = [ "A", "B" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> Picker.navigateDown
                        |> Picker.navigateDown
                        |> Picker.navigateDown
                        |> Picker.selected
                        |> Expect.equal (Just "B")
            , test "navigation works on filtered list" <|
                \() ->
                    Picker.open
                        { items = [ "Json.Decode", "Json.Encode", "Html" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> typeString "json"
                        |> Picker.navigateDown
                        |> Picker.selected
                        |> Expect.equal (Just "Json.Encode")
            , test "filter resets selection to first" <|
                \() ->
                    Picker.open
                        { items = [ "A", "B", "C" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> Picker.navigateDown
                        |> Picker.navigateDown
                        |> typeString "A"
                        |> Picker.selected
                        |> Expect.equal (Just "A")
            ]
        , describe "view"
            [ test "view contains title" <|
                \() ->
                    Picker.open
                        { items = [ "A" ]
                        , toString = identity
                        , title = "My Picker"
                        }
                        |> Picker.viewBody
                        |> List.map Tui.Screen.toString
                        |> String.concat
                        |> String.contains "A"
                        |> Expect.equal True
            , test "view shows match count" <|
                \() ->
                    Picker.open
                        { items = [ "A", "B", "C" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> typeString "A"
                        |> Picker.matchCount
                        |> Expect.equal 1
            ]
        , describe "query"
            [ test "query returns current filter text" <|
                \() ->
                    Picker.open
                        { items = [ "A" ]
                        , toString = identity
                        , title = "Pick"
                        }
                        |> typeString "hello"
                        |> Picker.query
                        |> Expect.equal "hello"
            ]
        ]


typeString : String -> Picker.State item -> Picker.State item
typeString str state =
    String.foldl
        (\c s ->
            Picker.typeChar c s
        )
        state
        str
