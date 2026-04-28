module StepperDemo exposing (tuiTests)

import Ansi.Color
import BackendTask
import Test.BackendTask as BackendTaskTest
import Test.Tui as TuiTest
import Tui
import Tui.Layout as Layout
import Tui.Layout.Effect as Effect
import Tui.Layout.Test as LayoutTest
import Tui.Screen
import Tui.Sub


tuiTests : TuiTest.Test
tuiTests =
    TuiTest.test "layout stepper demo"
        (TuiTest.start BackendTaskTest.init appConfig)
        (LayoutTest.ensureFocusedPane "left"
            ++ LayoutTest.ensureSelectedIndex "left" 0
            ++ [ TuiTest.pressKeyN 3 'j' ]
            ++ LayoutTest.ensureSelectedIndex "left" 3
            ++ LayoutTest.ensurePaneHas "Left" "delta"
            ++ [ TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] } ]
            ++ LayoutTest.ensureFocusedPane "right"
            ++ LayoutTest.ensurePaneHas "Right" "details"
            ++ LayoutTest.ensurePaneDoesNotHave "Right" "alpha"
            ++ [ TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] } ]
            ++ LayoutTest.ensureFocusedPane "left"
            ++ [ TuiTest.ensureViewHasStyled [ TuiTest.bold ] "delta"
               , TuiTest.expectRunning
               ]
        )


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


items : List String
items =
    [ "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel" ]


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
                            Layout.Selected { focused } ->
                                Tui.Screen.text ("▸ " ++ item)
                                    |> Tui.Screen.bold
                                    |> (if focused then
                                            Tui.Screen.bg Ansi.Color.blue

                                        else
                                            identity
                                       )

                            Layout.NotSelected ->
                                Tui.Screen.text ("  " ++ item)
                }
                items
            )
        , Layout.pane "right"
            { title = "Right", width = Layout.fill }
            (Layout.content [ Tui.Screen.text "details here" ])
        ]
