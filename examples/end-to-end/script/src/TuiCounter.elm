module TuiCounter exposing (run)

{-| A minimal TUI demo — a counter you can increment/decrement with keyboard.

    elm - pages run script / src / TuiCounter.elm

Keys:
k / ↑ — increment
j / ↓ — decrement
q / Esc — quit

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import Pages.Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Screen exposing (plain)
import Tui.Sub


type alias Model =
    { count : Int
    }


type Msg
    = KeyPressed Tui.Sub.KeyEvent


run : Script
run =
    Tui.program
        { data = BackendTask.succeed ()
        , init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
        |> Tui.toScript


init : () -> ( Model, Effect.Effect Msg )
init () =
    ( { count = 0 }
    , Effect.none
    )


update : Msg -> Model -> ( Model, Effect.Effect Msg )
update msg model =
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Sub.Character 'k' ->
                    ( { model | count = model.count + 1 }, Effect.none )

                Tui.Sub.Arrow Tui.Sub.Up ->
                    ( { model | count = model.count + 1 }, Effect.none )

                Tui.Sub.Character 'j' ->
                    ( { model | count = model.count - 1 }, Effect.none )

                Tui.Sub.Arrow Tui.Sub.Down ->
                    ( { model | count = model.count - 1 }, Effect.none )

                Tui.Sub.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Sub.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )


view : Tui.Context -> Model -> Tui.Screen.Screen
view ctx model =
    let
        dimStyle =
            { plain | attributes = [ Tui.Screen.Dim ] }
    in
    Tui.Screen.lines
        [ Tui.Screen.text ""
        , Tui.Screen.styled { plain | fg = Just Ansi.Color.cyan, attributes = [ Tui.Screen.Bold ] }
            "  TUI Counter Demo"
        , Tui.Screen.text ""
        , Tui.Screen.concat
            [ Tui.Screen.text "  Count: "
            , Tui.Screen.styled
                { plain | fg =
                        Just
                            (if model.count >= 0 then
                                Ansi.Color.green

                             else
                                Ansi.Color.red
                            )
                    , attributes = [ Tui.Screen.Bold ]
                }
                (String.fromInt model.count)
            ]
        , Tui.Screen.text ""
        , Tui.Screen.styled dimStyle "  k/↑  increment"
        , Tui.Screen.styled dimStyle "  j/↓  decrement"
        , Tui.Screen.styled dimStyle "  q    quit"
        , Tui.Screen.text ""
        , Tui.Screen.styled dimStyle
            ("  Terminal: "
                ++ String.fromInt ctx.width
                ++ "×"
                ++ String.fromInt ctx.height
            )
        ]


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.onKeyPress KeyPressed
