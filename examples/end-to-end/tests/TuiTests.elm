module TuiTests exposing (suite, tuiTests)

import Test
import Tui
import Tui.Effect as Effect
import Tui.Screen
import Tui.Sub
import Tui.Test as TuiTest


type Msg
    = Increment
    | Quit


tuiTests : TuiTest.Test
tuiTests =
    TuiTest.describe "Counter"
        [ TuiTest.test "increments and exits"
            (counterApp
                |> TuiTest.pressKey 'j'
                |> TuiTest.ensureViewHas "Count: 1"
                |> TuiTest.pressKey 'q'
                |> TuiTest.expectExit
            )
        ]


suite : Test.Test
suite =
    TuiTest.toTest tuiTests


counterApp : TuiTest.TuiTest Int Msg
counterApp =
    TuiTest.start
        { data = ()
        , init = \() -> ( 0, Effect.none )
        , update = update
        , view = view
        , subscriptions = \_ -> Tui.Sub.onKeyPress keyToMsg
        }


update : Msg -> Int -> ( Int, Effect.Effect Msg )
update msg count =
    case msg of
        Increment ->
            ( count + 1, Effect.none )

        Quit ->
            ( count, Effect.exit )


view : Tui.Context -> Int -> Tui.Screen.Screen
view _ count =
    Tui.Screen.text ("Count: " ++ String.fromInt count)


keyToMsg : Tui.Sub.KeyEvent -> Msg
keyToMsg event =
    case event.key of
        Tui.Sub.Character 'j' ->
            Increment

        Tui.Sub.Character 'q' ->
            Quit

        _ ->
            Quit
