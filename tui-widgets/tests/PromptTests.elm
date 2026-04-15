module PromptTests exposing (suite)

import Expect
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Tui
import Tui.Event
import Tui.Prompt as Prompt
import Tui.Screen


suite : Test
suite =
    describe "Tui.Prompt"
        [ describe "cursor rendering"
            [ test "unmasked prompt shows an inverse cursor in the rendered body" <|
                \() ->
                    Prompt.open { title = "Name", placeholder = "" }
                        |> typeString "hello"
                        |> renderBodyJson
                        |> expectContains "\"inverse\":true"
            , test "masked prompt still shows an inverse cursor in the rendered body" <|
                \() ->
                    Prompt.open { title = "Password", placeholder = "" }
                        |> Prompt.withMasking
                        |> typeString "secret"
                        |> renderBodyJson
                        |> expectContains "\"inverse\":true"
            ]
        , describe "suggestion navigation"
            [ test "ArrowDown then Tab accepts the second suggestion" <|
                \() ->
                    let
                        state =
                            Prompt.open { title = "Fruit", placeholder = "" }
                                |> Prompt.withSuggestions fruitSuggestions
                                |> typeString "ap"

                        ( afterDown, _ ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Event.Arrow Tui.Event.Down, modifiers = [] }
                                state

                        ( afterTab, _ ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Event.Tab, modifiers = [] }
                                afterDown
                    in
                    Prompt.text afterTab
                        |> Expect.equal "apricot"
            ]
        ]


typeString : String -> Prompt.State -> Prompt.State
typeString str state =
    String.foldl
        (\c currentState ->
            Prompt.handleKeyEvent
                { key = Tui.Event.Character c, modifiers = [] }
                currentState
                |> Tuple.first
        )
        state
        str


renderBodyJson : Prompt.State -> String
renderBodyJson state =
    Prompt.viewBody { width = 40 } state
        |> Tui.Screen.lines
        |> Tui.Screen.encodeScreen
        |> Encode.encode 0


expectContains : String -> String -> Expect.Expectation
expectContains needle haystack =
    if String.contains needle haystack then
        Expect.pass

    else
        Expect.fail
            ("Expected to find "
                ++ needle
                ++ " in:\n\n"
                ++ haystack
            )


fruitSuggestions : String -> List String
fruitSuggestions query =
    [ "apple", "apricot", "banana" ]
        |> List.filter (String.contains query)
