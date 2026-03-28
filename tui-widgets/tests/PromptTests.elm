module PromptTests exposing (suite)

import Expect
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Tui
import Tui.Internal
import Tui.Prompt as Prompt


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
        ]


typeString : String -> Prompt.State -> Prompt.State
typeString str state =
    String.foldl
        (\c currentState ->
            Prompt.handleKeyEvent
                { key = Tui.Character c, modifiers = [] }
                currentState
                |> Tuple.first
        )
        state
        str


renderBodyJson : Prompt.State -> String
renderBodyJson state =
    Prompt.viewBody { width = 40 } state
        |> Tui.lines
        |> Tui.Internal.encodeScreen
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
