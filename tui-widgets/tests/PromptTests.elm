module PromptTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Prompt as Prompt
import Tui.Screen
import Tui.Sub


suite : Test
suite =
    describe "Tui.Prompt"
        [ describe "cursor rendering"
            [ test "unmasked prompt shows an inverse cursor in the rendered body" <|
                \() ->
                    Prompt.open { title = "Name", placeholder = "" }
                        |> typeString "hello"
                        |> renderedBodyHasInverseCursor
                        |> Expect.equal True
            , test "masked prompt still shows an inverse cursor in the rendered body" <|
                \() ->
                    Prompt.open { title = "Password", placeholder = "" }
                        |> Prompt.withMasking
                        |> typeString "secret"
                        |> renderedBodyHasInverseCursor
                        |> Expect.equal True
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
                                { key = Tui.Sub.Arrow Tui.Sub.Down, modifiers = [] }
                                state

                        ( afterTab, _ ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Tab, modifiers = [] }
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
                { key = Tui.Sub.Character c, modifiers = [] }
                currentState
                |> Tuple.first
        )
        state
        str


renderedBodyHasInverseCursor : Prompt.State -> Bool
renderedBodyHasInverseCursor state =
    Prompt.viewBody { width = 40 } state
        |> Tui.Screen.lines
        |> Tui.Screen.toSpanLines
        |> List.concat
        |> List.any (\span -> List.member Tui.Screen.Inverse span.style.attributes)


fruitSuggestions : String -> List String
fruitSuggestions query =
    [ "apple", "apricot", "banana" ]
        |> List.filter (String.contains query)
