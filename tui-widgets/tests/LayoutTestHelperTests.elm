module LayoutTestHelperTests exposing (suite)

import Ansi.Color
import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Layout as Layout
import Tui.Layout.Test as LayoutTest
import Test.Runner
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
            , test "Tab moves focus to second pane" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyWith { key = Tui.Tab, modifiers = [] }
                        |> LayoutTest.ensureFocusedPane "right"
                        |> TuiTest.expectRunning
            , test "Tab Tab moves focus back to first pane" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyWith { key = Tui.Tab, modifiers = [] }
                        |> TuiTest.pressKeyWith { key = Tui.Tab, modifiers = [] }
                        |> LayoutTest.ensureFocusedPane "left"
                        |> TuiTest.expectRunning
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
            , test "j moves selection down" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyN 3 'j'
                        |> LayoutTest.ensureSelectedIndex "left" 3
                        |> TuiTest.expectRunning
            , test "j then k moves selection back" <|
                \() ->
                    twoPane
                        |> TuiTest.pressKeyN 2 'j'
                        |> TuiTest.pressKey 'k'
                        |> LayoutTest.ensureSelectedIndex "left" 1
                        |> TuiTest.expectRunning
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
            , test "left pane has list items" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneHas "Left" "alpha"
                        |> TuiTest.expectRunning
            , test "right pane does not have left pane content" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneDoesNotHave "Right" "alpha"
                        |> TuiTest.expectRunning
            , test "left pane does not have right pane content" <|
                \() ->
                    twoPane
                        |> LayoutTest.ensurePaneDoesNotHave "Left" "details here"
                        |> TuiTest.expectRunning
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
    case tuiTest |> TuiTest.expectRunning of
        -- expectRunning returns a failed Expectation when there's an error,
        -- which means our assertion did fail as expected. Check the message.
        _ ->
            -- We need to extract the error. Use ensureView to probe for it.
            -- Actually, the trick is: if the test has an error, expectRunning
            -- will Expect.fail with the error message. We can check that.
            let
                result : Expect.Expectation
                result =
                    TuiTest.expectRunning tuiTest
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
        { init = \() -> ( (), Effect.none )
        , update = \_ _ model -> ( model, Effect.none )
        , view = appView
        , bindings = \_ _ -> []
        , status = \_ -> { waiting = Nothing }
        , modal = \_ -> Nothing
        , onRawEvent = Nothing
        }


twoPane : TuiTest.TuiTest (Layout.FrameworkModel () Msg) (Layout.FrameworkMsg Msg)
twoPane =
    TuiTest.startApp () appConfig


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
                                Tui.text ("▸ " ++ item)

                            Layout.NotSelected ->
                                Tui.text ("  " ++ item)
                }
                items
            )
        , Layout.pane "right"
            { title = "Right", width = Layout.fill }
            (Layout.content [ Tui.text "details here" ])
        ]
