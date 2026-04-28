module StyledAssertionTests exposing (suite)

import Ansi.Color
import BackendTask
import Expect
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Tui as TuiTest
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Screen
import Tui.Sub


suite : Test
suite =
    describe "Styled text assertions"
        [ describe "ensureViewHasStyled basics"
            [ test "finds bold text" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.bold ] "Bold text"
                        , TuiTest.expectRunning
                        ]
            , test "finds text with foreground color" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "Error: failed"
                        , TuiTest.expectRunning
                        ]
            , test "finds text with background color" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.bg Ansi.Color.blue ] "Selected"
                        , TuiTest.expectRunning
                        ]
            , test "finds dim text" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.dim ] "dimmed"
                        , TuiTest.expectRunning
                        ]
            , test "plain text does NOT match bold check" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bold ] "Normal text"
                        , TuiTest.expectRunning
                        ]
            , test "red text does NOT match blue bg check" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bg Ansi.Color.blue ] "Error: failed"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "combined style checks"
            [ test "matches text with both bold AND foreground color" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.bold, TuiTest.fg Ansi.Color.yellow ] "Warning"
                        , TuiTest.expectRunning
                        ]
            , test "fails when only one of two checks matches" <|
                \() ->
                    -- "Bold text" is bold but NOT yellow
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bold, TuiTest.fg Ansi.Color.yellow ] "Bold text"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "span merging — adjacent spans with same style"
            [ test "merges adjacent red spans into one match" <|
                \() ->
                    -- The view renders "ERROR" and " Error message" as separate red spans
                    TuiTest.expect fragmentedApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "ERROR Error message"
                        , TuiTest.expectRunning
                        ]
            , test "does NOT merge spans across a style boundary" <|
                \() ->
                    -- "Normal" is unstyled, "Bold" is bold — they're adjacent but different styles
                    TuiTest.expect fragmentedApp
                        [ TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bold ] "Normal Bold"
                        , TuiTest.expectRunning
                        ]
            , test "merges three adjacent bold spans" <|
                \() ->
                    TuiTest.expect fragmentedApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.bold ] "one two three"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "substring matching within styled region"
            [ test "finds substring within a larger styled region" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.bold ] "Bold"
                        , TuiTest.expectRunning
                        ]
            , test "finds substring spanning merged fragments" <|
                \() ->
                    -- "ERROR Error" spans the boundary between the two red fragments
                    TuiTest.expect fragmentedApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "ERROR Error"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "multiline"
            [ test "styled text on different lines both findable" <|
                \() ->
                    TuiTest.expect styledApp
                        [ TuiTest.ensureViewHasStyled [ TuiTest.bold ] "Bold text"
                        , TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "Error: failed"
                        , TuiTest.expectRunning
                        ]
            ]
        ]



-- Test app with various styled text


type alias StyledModel =
    ()


type StyledMsg
    = NoOp


styledApp : TuiTest.TuiTest StyledModel StyledMsg
styledApp =
    TuiTest.start BackendTaskTest.init
        { data = BackendTask.succeed ()
        , init = \() -> ( (), Effect.none )
        , update = \_ model -> ( model, Effect.none )
        , view = styledView
        , subscriptions = \_ -> Tui.Sub.none
        }


styledView : Tui.Context -> StyledModel -> Tui.Screen.Screen
styledView _ _ =
    Tui.Screen.lines
        [ Tui.Screen.text "Normal text"
        , Tui.Screen.text "Bold text" |> Tui.Screen.bold
        , Tui.Screen.text "Error: failed" |> Tui.Screen.fg Ansi.Color.red
        , Tui.Screen.text "Selected" |> Tui.Screen.bg Ansi.Color.blue
        , Tui.Screen.text "dimmed" |> Tui.Screen.dim
        , Tui.Screen.text "Warning" |> Tui.Screen.bold |> Tui.Screen.fg Ansi.Color.yellow
        ]



-- Test app with fragmented spans (adjacent spans, same style)


fragmentedApp : TuiTest.TuiTest StyledModel StyledMsg
fragmentedApp =
    TuiTest.start BackendTaskTest.init
        { data = BackendTask.succeed ()
        , init = \() -> ( (), Effect.none )
        , update = \_ model -> ( model, Effect.none )
        , view = fragmentedView
        , subscriptions = \_ -> Tui.Sub.none
        }


fragmentedView : Tui.Context -> StyledModel -> Tui.Screen.Screen
fragmentedView _ _ =
    Tui.Screen.lines
        [ -- Two adjacent red spans — should merge for assertion purposes
          Tui.Screen.concat
            [ Tui.Screen.text "ERROR" |> Tui.Screen.fg Ansi.Color.red
            , Tui.Screen.text " Error message" |> Tui.Screen.fg Ansi.Color.red
            ]

        -- Style boundary: unstyled then bold, should NOT merge
        , Tui.Screen.concat
            [ Tui.Screen.text "Normal "
            , Tui.Screen.text "Bold" |> Tui.Screen.bold
            ]

        -- Three adjacent bold spans
        , Tui.Screen.concat
            [ Tui.Screen.text "one " |> Tui.Screen.bold
            , Tui.Screen.text "two " |> Tui.Screen.bold
            , Tui.Screen.text "three" |> Tui.Screen.bold
            ]
        ]
