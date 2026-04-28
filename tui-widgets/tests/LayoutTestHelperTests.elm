module LayoutTestHelperTests exposing (suite)

import Ansi.Color
import BackendTask
import Expect
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.Runner
import Test.Tui as TuiTest
import Tui
import Tui.Layout as Layout
import Tui.Layout.Effect as Effect exposing (Effect)
import Tui.Layout.Test as LayoutTest
import Tui.Screen
import Tui.Sub


suite : Test
suite =
    describe "Tui.Layout.Test helpers"
        [ describe "ensureFocusedPane"
            [ test "initial focus is first pane" <|
                \() ->
                    TuiTest.expect twoPane
                        (LayoutTest.ensureFocusedPane "left"
                            ++ [ TuiTest.expectRunning ]
                        )
            , test "Tab moves focus to second pane" <|
                \() ->
                    TuiTest.expect twoPane
                        ([ TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] } ]
                            ++ LayoutTest.ensureFocusedPane "right"
                            ++ [ TuiTest.expectRunning ]
                        )
            , test "Tab Tab moves focus back to first pane" <|
                \() ->
                    TuiTest.expect twoPane
                        ([ TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                         , TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                         ]
                            ++ LayoutTest.ensureFocusedPane "left"
                            ++ [ TuiTest.expectRunning ]
                        )
            ]
        , describe "ensureFocusedPane error messages"
            [ test "names expected and actual pane" <|
                \() ->
                    -- Focus is on "left", assert "right" to trigger failure
                    TuiTest.expect twoPane (LayoutTest.ensureFocusedPane "right")
                        |> expectFailureContaining "expected focused pane to be \"right\" but it was \"left\""
            ]
        , describe "ensureSelectedIndex"
            [ test "initial selection is 0" <|
                \() ->
                    TuiTest.expect twoPane
                        (LayoutTest.ensureSelectedIndex "left" 0
                            ++ [ TuiTest.expectRunning ]
                        )
            , test "j moves selection down" <|
                \() ->
                    TuiTest.expect twoPane
                        ([ TuiTest.pressKeyN 3 'j' ]
                            ++ LayoutTest.ensureSelectedIndex "left" 3
                            ++ [ TuiTest.expectRunning ]
                        )
            , test "j then k moves selection back" <|
                \() ->
                    TuiTest.expect twoPane
                        ([ TuiTest.pressKeyN 2 'j'
                         , TuiTest.pressKey 'k'
                         ]
                            ++ LayoutTest.ensureSelectedIndex "left" 1
                            ++ [ TuiTest.expectRunning ]
                        )
            ]
        , describe "ensureSelectedIndex error messages"
            [ test "names pane and shows expected vs actual index" <|
                \() ->
                    TuiTest.expect twoPane
                        ([ TuiTest.pressKeyN 3 'j' ]
                            ++ LayoutTest.ensureSelectedIndex "left" 5
                        )
                        |> expectFailureContaining "expected pane \"left\" to have selected index 5 but it was 3"
            ]
        , describe "ensureScrollPosition"
            [ test "initial scroll is 0" <|
                \() ->
                    TuiTest.expect twoPane
                        (LayoutTest.ensureScrollPosition "left" 0
                            ++ [ TuiTest.expectRunning ]
                        )
            ]
        , describe "ensureScrollPosition error messages"
            [ test "names pane and shows expected vs actual position" <|
                \() ->
                    TuiTest.expect twoPane (LayoutTest.ensureScrollPosition "left" 42)
                        |> expectFailureContaining "expected pane \"left\" to have scroll position 42 but it was 0"
            ]
        , describe "ensurePaneHas"
            [ test "finds text in the correct pane" <|
                \() ->
                    TuiTest.expect twoPane
                        (LayoutTest.ensurePaneHas "Right" "details here"
                            ++ [ TuiTest.expectRunning ]
                        )
            , test "left pane has list items" <|
                \() ->
                    TuiTest.expect twoPane
                        (LayoutTest.ensurePaneHas "Left" "alpha"
                            ++ [ TuiTest.expectRunning ]
                        )
            , test "right pane does not have left pane content" <|
                \() ->
                    TuiTest.expect twoPane
                        (LayoutTest.ensurePaneDoesNotHave "Right" "alpha"
                            ++ [ TuiTest.expectRunning ]
                        )
            , test "left pane does not have right pane content" <|
                \() ->
                    TuiTest.expect twoPane
                        (LayoutTest.ensurePaneDoesNotHave "Left" "details here"
                            ++ [ TuiTest.expectRunning ]
                        )
            ]
        , describe "ensurePaneHas error messages"
            [ test "shows pane title and needle on failure" <|
                \() ->
                    TuiTest.expect twoPane (LayoutTest.ensurePaneHas "Right" "nonexistent text")
                        |> expectFailureContaining "expected pane \"Right\" to contain"
            , test "shows pane content on failure" <|
                \() ->
                    TuiTest.expect twoPane (LayoutTest.ensurePaneHas "Right" "nonexistent text")
                        |> expectFailureContaining "details here"
            , test "shows helpful message when pane title not found" <|
                \() ->
                    TuiTest.expect twoPane (LayoutTest.ensurePaneHas "Nonexistent" "anything")
                        |> expectFailureContaining "could not find pane titled \"Nonexistent\""
            ]
        ]


{-| Assert that an Expectation failed with a message containing the given
substring.
-}
expectFailureContaining : String -> Expect.Expectation -> Expect.Expectation
expectFailureContaining expectedSubstring expectation =
    case Test.Runner.getFailureReason expectation of
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
