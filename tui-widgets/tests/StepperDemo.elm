module StepperDemo exposing (run)

import Ansi.Color
import Pages.Script as Script
import Tui
import Tui.Effect as Effect
import Tui.Layout as Layout
import Tui.Layout.Test as LayoutTest
import Tui.Test as TuiTest
import Tui.Test.Stepper


run : Script.Script
run =
    TuiTest.startApp () appConfig
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
        |> Tui.Test.Stepper.run


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
                                    |> (if focused then Tui.bg Ansi.Color.blue else identity)

                            Layout.NotSelected ->
                                Tui.text ("  " ++ item)
                }
                items
            )
        , Layout.pane "right"
            { title = "Right", width = Layout.fill }
            (Layout.content [ Tui.text "details here" ])
        ]
