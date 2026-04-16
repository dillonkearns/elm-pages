module LayoutTestHelperTests exposing (suite)

import Ansi.Color
import BackendTask
import Expect
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Runner
import Tui
import Tui.Layout as Layout
import Tui.Layout.Effect as Effect exposing (Effect)
import Tui.Layout.Test as LayoutTest
import Tui.Screen
import Tui.Sub
import Tui.Test as TuiTest


suite : Test
suite =
    describe "Tui.Layout.Test helpers"
        [ describe "ensureFocusedPane"
            [ test "initial focus is first pane" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensureFocusedPane "left"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "Tab moves focus to second pane" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                        |> LayoutTest.ensureFocusedPane "right"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "Tab Tab moves focus back to first pane" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                        |> LayoutTest.ensureFocusedPane "left"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "ensureFocusedPane error messages"
            [ test "names expected and actual pane" <|
                \() ->
                    twoPane
                        -- Focus is on "left", assert "right" to trigger failure
                        |> LayoutTest.ensureFocusedPane "right"
                        |> expectFailureContaining "expected focused pane to be \"right\" but it was \"left\""
            ]
        , describe "ensureSelectedIndex"
            [ test "initial selection is 0" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensureSelectedIndex "left" 0
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "j moves selection down" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyN 3 'j'
                        |> LayoutTest.ensureSelectedIndex "left" 3
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "j then k moves selection back" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyN 2 'j'
                        |> TuiTest.pressKey 'k'
                        |> LayoutTest.ensureSelectedIndex "left" 1
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "ensureSelectedIndex error messages"
            [ test "names pane and shows expected vs actual index" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyN 3 'j'
                        |> LayoutTest.ensureSelectedIndex "left" 5
                        |> expectFailureContaining "expected pane \"left\" to have selected index 5 but it was 3"
            ]
        , describe "ensureScrollPosition"
            [ test "initial scroll is 0" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensureScrollPosition "left" 0
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "ensureScrollPosition error messages"
            [ test "names pane and shows expected vs actual position" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensureScrollPosition "left" 42
                        |> expectFailureContaining "expected pane \"left\" to have scroll position 42 but it was 0"
            ]
        , describe "ensurePaneHas"
            [ test "finds text in the correct pane" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneHas "Right" "details here"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "left pane has list items" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneHas "Left" "alpha"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "right pane does not have left pane content" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneDoesNotHave "Right" "alpha"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "left pane does not have right pane content" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneDoesNotHave "Left" "details here"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "ensurePaneHas error messages"
            [ test "shows pane title and needle on failure" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneHas "Right" "nonexistent text"
                        |> expectFailureContaining "expected pane \"Right\" to contain"
            , test "shows pane content on failure" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneHas "Right" "nonexistent text"
                        |> expectFailureContaining "details here"
            , test "shows helpful message when pane title not found" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneHas "Nonexistent" "anything"
                        |> expectFailureContaining "could not find pane titled \"Nonexistent\""
            ]
        ]


{-| Assert that the TuiTest is in a failed state with a message containing
the given substring.
-}
expectFailureContaining : String -> TuiTest.TuiTest model msg -> Expect.Expectation
expectFailureContaining expectedSubstring tuiTest =
    case
        tuiTest
            |> TuiTest.expectRunning
            |> TuiTest.done
    of
        -- expectRunning returns a failed Outcome when there's an error,
        -- which means our assertion did fail as expected. Check the message.
        _ ->
            -- We need to extract the error. Use ensureView to probe for it.
            -- Actually, the trick is: if the test has an error, expectRunning
            -- will Expect.fail with the error message. We can check that.
            let
                result : Expect.Expectation
                result =
                    TuiTest.expectRunning tuiTest
                        |> TuiTest.done
            in
            case Test.Runner.getFailureReason result of
                Just reason ->
                    if String.contains expectedSubstring reason.description then
                        Expect.pass

                    else
                        Expect.fail
                            ("Expected failure message to contain:\n\n    \""
                                ++ expectedSubstring
                                ++ "\"\n\nbut the failure message was:\n\n    \""
                                ++ reason.description
                                ++ "\""
                            )

                Nothing ->
                    Expect.fail
                        ("Expected assertion to fail with message containing \""
                            ++ expectedSubstring
                            ++ "\" but the test passed"
                        )


items : List String
items =
    [ "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel" ]


type Msg
    = SelectItem String


appConfig =
    Layout.compileApp
        { data = BackendTask.succeed ()
        , init = \() -> ( (), Effect.none )
        , update = \_ _ model -> ( model, Effect.none )
        , view = appView
        , bindings = \_ _ -> []
        , status = \_ -> { waiting = Nothing }
        , modal = \_ -> Nothing
        , onRawEvent = Nothing
        }


twoPane : TuiTest.TuiTest (Layout.FrameworkModel () Msg) (Layout.FrameworkMsg Msg)
twoPane =
    TuiTest.start BackendTaskTest.init appConfig


appView : Tui.Context -> () -> Layout.Layout Msg
appView _ _ =
    Layout.horizontal
        [ Layout.pane "left"
            { title = "Left", width = Layout.fill }
            (Layout.selectableList
                { onSelect = SelectItem
                , view =
                    \{ selection } item ->
                        case selection of
                            Layout.Selected _ ->
                                Tui.Screen.text ("▸ " ++ item)

                            Layout.NotSelected ->
                                Tui.Screen.text ("  " ++ item)
                }
                items
            )
        , Layout.pane "right"
            { title = "Right", width = Layout.fill }
            (Layout.content [ Tui.Screen.text "details here" ])
        ]
