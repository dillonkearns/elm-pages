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
import Pages.Script as Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Sub


type alias Model =
    { count : Int
    }


type Msg
    = KeyPressed Tui.KeyEvent


run : Script
run =
    Script.tui
        { data = BackendTask.succeed ()
        , init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


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
                Tui.Character 'k' ->
                    ( { model | count = model.count + 1 }, Effect.none )

                Tui.Arrow Tui.Up ->
                    ( { model | count = model.count + 1 }, Effect.none )

                Tui.Character 'j' ->
                    ( { model | count = model.count - 1 }, Effect.none )

                Tui.Arrow Tui.Down ->
                    ( { model | count = model.count - 1 }, Effect.none )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )


view : Tui.Context -> Model -> Tui.Screen
view ctx model =
    let
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] }
    in
    Tui.lines
        [ Tui.text ""
        , Tui.styled { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.bold ] }
            "  TUI Counter Demo"
        , Tui.text ""
        , Tui.concat
            [ Tui.text "  Count: "
            , Tui.styled
                { fg =
                    Just
                        (if model.count >= 0 then
                            Ansi.Color.green

                         else
                            Ansi.Color.red
                        )
                , bg = Nothing
                , attributes = [ Tui.bold ]
                }
                (String.fromInt model.count)
            ]
        , Tui.text ""
        , Tui.styled dimStyle "  k/↑  increment"
        , Tui.styled dimStyle "  j/↓  decrement"
        , Tui.styled dimStyle "  q    quit"
        , Tui.text ""
        , Tui.styled dimStyle
            ("  Terminal: "
                ++ String.fromInt ctx.width
                ++ "×"
                ++ String.fromInt ctx.height
            )
        ]


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.onKeyPress KeyPressed
