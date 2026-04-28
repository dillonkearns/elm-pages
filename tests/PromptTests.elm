module PromptTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui.Prompt as Prompt
import Tui.Screen
import Tui.Sub


suite : Test
suite =
    describe "Tui.Prompt"
        [ describe "basic input"
            [ test "typing adds characters" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            Prompt.open { title = "Name", placeholder = "" }

                        ( s1, _ ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Character 'h', modifiers = [] }
                                state

                        ( s2, _ ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Character 'i', modifiers = [] }
                                s1
                    in
                    Prompt.text s2 |> Expect.equal "hi"
            , test "Enter submits the text" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            typeString "hello" (Prompt.open { title = "Name", placeholder = "" })

                        ( _, result ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Enter, modifiers = [] }
                                state
                    in
                    result |> Expect.equal (Prompt.Submitted "hello")
            , test "Escape cancels" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            typeString "partial" (Prompt.open { title = "Name", placeholder = "" })

                        ( _, result ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Escape, modifiers = [] }
                                state
                    in
                    result |> Expect.equal Prompt.Cancelled
            , test "typing returns Continue" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            Prompt.open { title = "Name", placeholder = "" }

                        ( _, result ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Character 'a', modifiers = [] }
                                state
                    in
                    result |> Expect.equal Prompt.Continue
            , test "Backspace removes last character" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            typeString "hello" (Prompt.open { title = "Name", placeholder = "" })

                        ( s1, _ ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Backspace, modifiers = [] }
                                state
                    in
                    Prompt.text s1 |> Expect.equal "hell"
            ]
        , describe "title"
            [ test "title returns the configured title" <|
                \() ->
                    Prompt.open { title = "Branch name", placeholder = "" }
                        |> Prompt.title
                        |> Expect.equal "Branch name"
            ]
        , describe "masking"
            [ test "masked prompt hides text in view" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            Prompt.open { title = "Password", placeholder = "" }
                                |> Prompt.withMasking
                                |> typeString "secret"

                        rendered : String
                        rendered =
                            Prompt.viewBody { width = 40 } state
                                |> List.map Tui.Screen.toString
                                |> String.join "\n"
                    in
                    Expect.all
                        [ -- Should NOT show the actual text
                          \r -> r |> String.contains "secret" |> Expect.equal False
                        , -- Should show mask characters
                          \r -> r |> String.contains "******" |> Expect.equal True
                        ]
                        rendered
            , test "masked prompt still returns real text on Submit" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            Prompt.open { title = "Password", placeholder = "" }
                                |> Prompt.withMasking
                                |> typeString "secret"

                        ( _, result ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Enter, modifiers = [] }
                                state
                    in
                    result |> Expect.equal (Prompt.Submitted "secret")
            ]
        , describe "suggestions"
            [ test "suggestions appear based on input" <|
                \() ->
                    let
                        suggest : String -> List String
                        suggest query =
                            [ "apple", "apricot", "banana" ]
                                |> List.filter (String.contains query)

                        state : Prompt.State
                        state =
                            Prompt.open { title = "Fruit", placeholder = "" }
                                |> Prompt.withSuggestions suggest
                                |> typeString "ap"

                        rendered : String
                        rendered =
                            Prompt.viewBody { width = 40 } state
                                |> List.map Tui.Screen.toString
                                |> String.join "\n"
                    in
                    Expect.all
                        [ \r -> r |> String.contains "apple" |> Expect.equal True
                        , \r -> r |> String.contains "apricot" |> Expect.equal True
                        , \r -> r |> String.contains "banana" |> Expect.equal False
                        ]
                        rendered
            , test "Tab selects the first suggestion" <|
                \() ->
                    let
                        suggest : String -> List String
                        suggest query =
                            [ "apple", "apricot", "banana" ]
                                |> List.filter (String.contains query)

                        state : Prompt.State
                        state =
                            Prompt.open { title = "Fruit", placeholder = "" }
                                |> Prompt.withSuggestions suggest
                                |> typeString "ap"

                        ( s1, _ ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Tab, modifiers = [] }
                                state
                    in
                    Prompt.text s1 |> Expect.equal "apple"
            , test "Tab then Enter submits the suggestion" <|
                \() ->
                    let
                        suggest : String -> List String
                        suggest query =
                            [ "apple", "apricot", "banana" ]
                                |> List.filter (String.contains query)

                        state : Prompt.State
                        state =
                            Prompt.open { title = "Fruit", placeholder = "" }
                                |> Prompt.withSuggestions suggest
                                |> typeString "ap"

                        ( s1, _ ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Tab, modifiers = [] }
                                state

                        ( _, result ) =
                            Prompt.handleKeyEvent
                                { key = Tui.Sub.Enter, modifiers = [] }
                                s1
                    in
                    result |> Expect.equal (Prompt.Submitted "apple")
            , test "no suggestions when input is empty" <|
                \() ->
                    let
                        suggest : String -> List String
                        suggest query =
                            [ "apple", "apricot", "banana" ]
                                |> List.filter (String.contains query)

                        state : Prompt.State
                        state =
                            Prompt.open { title = "Fruit", placeholder = "" }
                                |> Prompt.withSuggestions suggest

                        rendered : String
                        rendered =
                            Prompt.viewBody { width = 40 } state
                                |> List.map Tui.Screen.toString
                                |> String.join "\n"
                    in
                    rendered |> String.contains "apple" |> Expect.equal False
            ]
        , describe "viewBody"
            [ test "shows the input field" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            Prompt.open { title = "Name", placeholder = "" }
                                |> typeString "hello"

                        rendered : String
                        rendered =
                            Prompt.viewBody { width = 40 } state
                                |> List.map Tui.Screen.toString
                                |> String.join "\n"
                    in
                    rendered |> String.contains "hello" |> Expect.equal True
            , test "shows placeholder when empty" <|
                \() ->
                    let
                        state : Prompt.State
                        state =
                            Prompt.open { title = "Name", placeholder = "Type a name..." }

                        rendered : String
                        rendered =
                            Prompt.viewBody { width = 40 } state
                                |> List.map Tui.Screen.toString
                                |> String.join "\n"
                    in
                    rendered |> String.contains "Type a name..." |> Expect.equal True
            ]
        ]


typeString : String -> Prompt.State -> Prompt.State
typeString str state =
    String.foldl
        (\c s ->
            Prompt.handleKeyEvent
                { key = Tui.Sub.Character c, modifiers = [] }
                s
                |> Tuple.first
        )
        state
        str
