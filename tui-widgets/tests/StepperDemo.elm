module StepperDemo exposing (tuiTests)

import Ansi.Color
import BackendTask
import Tui
import Tui.Effect as Effect
import Tui.Layout as Layout
import Tui.Layout.Test as LayoutTest
import Tui.Test as TuiTest


tuiTests : TuiTest.Test
tuiTests =
    TuiTest.test "layout stepper demo"
        (TuiTest.startApp () appConfig
            |> LayoutTest.ensureFocusedPane "left"
            |> LayoutTest.ensureSelectedIndex "left" 0
            |> TuiTest.pressKeyN 3 'j'
            |> LayoutTest.ensureSelectedIndex "left" 3
            |> LayoutTest.ensurePaneHas "Left" "delta"
            |> TuiTest.pressKeyWith { key = Tui.Tab, modifiers = [] }
            |> LayoutTest.ensureFocusedPane "right"
            |> LayoutTest.ensurePaneHas "Right" "details"
            |> LayoutTest.ensurePaneDoesNotHave "Right" "alpha"
            |> TuiTest.pressKeyWith { key = Tui.Tab, modifiers = [] }
            |> LayoutTest.ensureFocusedPane "left"
            |> TuiTest.ensureViewHasStyled [ TuiTest.bold ] "delta"
            |> TuiTest.expectRunning
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
                                Tui.text ("▸ " ++ item)
                                    |> Tui.bold
                                    |> (if focused then
                                            Tui.bg Ansi.Color.blue

                                        else
                                            identity
                                       )

                            Layout.NotSelected ->
                                Tui.text ("  " ++ item)
                }
                items
            )
        , Layout.pane "right"
            { title = "Right", width = Layout.fill }
            (Layout.content [ Tui.text "details here" ])
        ]
