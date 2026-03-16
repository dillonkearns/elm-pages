module TuiCounter exposing (run)

{-| A minimal TUI demo — a counter you can increment/decrement with keyboard.

    elm-pages run script/src/TuiCounter.elm

Keys:
  k / ↑  — increment
  j / ↓  — decrement
  q / Esc — quit

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Sub as TuiSub


type alias Model =
    { count : Int
    }


type Msg
    = KeyPressed Tui.KeyEvent
    | Resized { width : Int, height : Int }


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

        Resized _ ->
            ( model, Effect.none )


view : Tui.Context -> Model -> Tui.Screen
view ctx model =
    Tui.lines
        [ Tui.text ""
        , Tui.styled [ Tui.bold, Tui.foreground Tui.cyan ]
            "  TUI Counter Demo"
        , Tui.text ""
        , Tui.concat
            [ Tui.text "  Count: "
            , Tui.styled
                [ Tui.bold
                , Tui.foreground
                    (if model.count >= 0 then
                        Tui.green

                     else
                        Tui.red
                    )
                ]
                (String.fromInt model.count)
            ]
        , Tui.text ""
        , Tui.styled [ Tui.dim ] "  k/↑  increment"
        , Tui.styled [ Tui.dim ] "  j/↓  decrement"
        , Tui.styled [ Tui.dim ] "  q    quit"
        , Tui.text ""
        , Tui.styled [ Tui.dim ]
            ("  Terminal: "
                ++ String.fromInt ctx.width
                ++ "×"
                ++ String.fromInt ctx.height
            )
        ]


subscriptions : Model -> TuiSub.Sub Msg
subscriptions _ =
    TuiSub.batch
        [ TuiSub.onKeyPress KeyPressed
        , TuiSub.onResize Resized
        ]
