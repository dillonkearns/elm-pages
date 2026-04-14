module StyledAssertionTests exposing (suite)

import Ansi.Color
import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Sub
import Tui.Test as TuiTest


suite : Test
suite =
    describe "Styled text assertions"
        [ describe "ensureViewHasStyled basics"
            [ test "finds bold text" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.bold ] "Bold text"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "finds text with foreground color" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "Error: failed"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "finds text with background color" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.bg Ansi.Color.blue ] "Selected"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "finds dim text" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.dim ] "dimmed"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "plain text does NOT match bold check" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bold ] "Normal text"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "red text does NOT match blue bg check" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bg Ansi.Color.blue ] "Error: failed"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "combined style checks"
            [ test "matches text with both bold AND foreground color" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.bold, TuiTest.fg Ansi.Color.yellow ] "Warning"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "fails when only one of two checks matches" <|
                \() ->
                    -- "Bold text" is bold but NOT yellow
                    styledApp
                        |> TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bold, TuiTest.fg Ansi.Color.yellow ] "Bold text"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "span merging — adjacent spans with same style"
            [ test "merges adjacent red spans into one match" <|
                \() ->
                    -- The view renders "ERROR" and " Error message" as separate red spans
                    fragmentedApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "ERROR Error message"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "does NOT merge spans across a style boundary" <|
                \() ->
                    -- "Normal" is unstyled, "Bold" is bold — they're adjacent but different styles
                    fragmentedApp
                        |> TuiTest.ensureViewDoesNotHaveStyled [ TuiTest.bold ] "Normal Bold"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "merges three adjacent bold spans" <|
                \() ->
                    fragmentedApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.bold ] "one two three"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "substring matching within styled region"
            [ test "finds substring within a larger styled region" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.bold ] "Bold"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "finds substring spanning merged fragments" <|
                \() ->
                    -- "ERROR Error" spans the boundary between the two red fragments
                    fragmentedApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "ERROR Error"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "multiline"
            [ test "styled text on different lines both findable" <|
                \() ->
                    styledApp
                        |> TuiTest.ensureViewHasStyled [ TuiTest.bold ] "Bold text"
                        |> TuiTest.ensureViewHasStyled [ TuiTest.fg Ansi.Color.red ] "Error: failed"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        ]



-- Test app with various styled text


type alias StyledModel =
    ()


type StyledMsg
    = NoOp


styledApp : TuiTest.TuiTest StyledModel StyledMsg
styledApp =
    TuiTest.start
        { data = ()
        , init = \() -> ( (), Effect.none )
        , update = \_ model -> ( model, Effect.none )
        , view = styledView
        , subscriptions = \_ -> Tui.Sub.none
        }


styledView : Tui.Context -> StyledModel -> Tui.Screen
styledView _ _ =
    Tui.lines
        [ Tui.text "Normal text"
        , Tui.text "Bold text" |> Tui.bold
        , Tui.text "Error: failed" |> Tui.fg Ansi.Color.red
        , Tui.text "Selected" |> Tui.bg Ansi.Color.blue
        , Tui.text "dimmed" |> Tui.dim
        , Tui.text "Warning" |> Tui.bold |> Tui.fg Ansi.Color.yellow
        ]



-- Test app with fragmented spans (adjacent spans, same style)


fragmentedApp : TuiTest.TuiTest StyledModel StyledMsg
fragmentedApp =
    TuiTest.start
        { data = ()
        , init = \() -> ( (), Effect.none )
        , update = \_ model -> ( model, Effect.none )
        , view = fragmentedView
        , subscriptions = \_ -> Tui.Sub.none
        }


fragmentedView : Tui.Context -> StyledModel -> Tui.Screen
fragmentedView _ _ =
    Tui.lines
        [ -- Two adjacent red spans — should merge for assertion purposes
          Tui.concat
            [ Tui.text "ERROR" |> Tui.fg Ansi.Color.red
            , Tui.text " Error message" |> Tui.fg Ansi.Color.red
            ]

        -- Style boundary: unstyled then bold, should NOT merge
        , Tui.concat
            [ Tui.text "Normal "
            , Tui.text "Bold" |> Tui.bold
            ]

        -- Three adjacent bold spans
        , Tui.concat
            [ Tui.text "one " |> Tui.bold
            , Tui.text "two " |> Tui.bold
            , Tui.text "three" |> Tui.bold
            ]
        ]
