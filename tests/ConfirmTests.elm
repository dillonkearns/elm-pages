module ConfirmTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Confirm as Confirm
import Tui.Screen


suite : Test
suite =
    describe "Tui.Confirm"
        [ describe "confirm"
            [ test "title is set" <|
                \() ->
                    Confirm.confirm
                        { title = "Delete branch?"
                        , message = "This cannot be undone."
                        }
                        |> Confirm.title
                        |> Expect.equal "Delete branch?"
            , test "message appears in body" <|
                \() ->
                    Confirm.confirm
                        { title = "Delete?"
                        , message = "Are you sure?"
                        }
                        |> Confirm.viewBody
                        |> List.map Tui.Screen.toString
                        |> String.concat
                        |> String.contains "Are you sure?"
                        |> Expect.equal True
            , test "shows yes/no hint" <|
                \() ->
                    Confirm.confirm
                        { title = "Delete?"
                        , message = "Sure?"
                        }
                        |> Confirm.viewFooter
                        |> (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "Enter" |> Expect.equal True
                                    , \str -> str |> String.contains "Esc" |> Expect.equal True
                                    ]
                                    s
                           )
            ]
        , describe "prompt"
            [ test "prompt has initial text" <|
                \() ->
                    Confirm.prompt
                        { title = "Branch name"
                        , initialValue = "feature/"
                        }
                        |> Confirm.inputText
                        |> Expect.equal "feature/"
            , test "prompt body shows input" <|
                \() ->
                    Confirm.prompt
                        { title = "Branch name"
                        , initialValue = "main"
                        }
                        |> Confirm.viewBody
                        |> List.map Tui.Screen.toString
                        |> String.concat
                        |> String.contains "main"
                        |> Expect.equal True
            , test "typing updates input" <|
                \() ->
                    Confirm.prompt
                        { title = "Name"
                        , initialValue = ""
                        }
                        |> Confirm.typeChar 'h'
                        |> Confirm.typeChar 'i'
                        |> Confirm.inputText
                        |> Expect.equal "hi"
            , test "backspace removes char" <|
                \() ->
                    Confirm.prompt
                        { title = "Name"
                        , initialValue = "hello"
                        }
                        |> Confirm.backspace
                        |> Confirm.inputText
                        |> Expect.equal "hell"
            ]
        , describe "isPrompt"
            [ test "confirm is not a prompt" <|
                \() ->
                    Confirm.confirm { title = "Sure?", message = "Really?" }
                        |> Confirm.isPrompt
                        |> Expect.equal False
            , test "prompt is a prompt" <|
                \() ->
                    Confirm.prompt { title = "Name", initialValue = "" }
                        |> Confirm.isPrompt
                        |> Expect.equal True
            ]
        ]
