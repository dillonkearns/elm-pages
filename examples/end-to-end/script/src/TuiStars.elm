module TuiStars exposing (run)

{-| TUI demo: type a GitHub repo name, press Enter to fetch star count.

    elm - pages run script / src / TuiStars.elm

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import BackendTask.Http
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Pages.Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Event
import Tui.Screen exposing (plain)
import Tui.Sub


type alias Model =
    { input : String
    , result : Result String Int
    , loading : Bool
    }


type Msg
    = KeyPressed Tui.Event.KeyEvent
    | GotStars (Result FatalError Int)


run : Script
run =
    Tui.program
        { data = BackendTask.succeed ()
        , init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


init : () -> ( Model, Effect.Effect Msg )
init () =
    ( { input = "dillonkearns/elm-pages"
      , result = Err "Press Enter to fetch"
      , loading = False
      }
    , Effect.none
    )


update : Msg -> Model -> ( Model, Effect.Effect Msg )
update msg model =
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Event.Escape ->
                    ( model, Effect.exit )

                Tui.Event.Character 'q' ->
                    if List.member Tui.Event.Ctrl event.modifiers then
                        ( model, Effect.exit )

                    else
                        ( { model
                            | input = model.input ++ "q"
                            , result = Err ""
                          }
                        , Effect.none
                        )

                Tui.Event.Enter ->
                    ( { model | loading = True, result = Err "Loading..." }
                    , fetchStars model.input
                    )

                Tui.Event.Backspace ->
                    ( { model
                        | input = String.dropRight 1 model.input
                        , result = Err ""
                      }
                    , Effect.none
                    )

                Tui.Event.Character c ->
                    ( { model
                        | input = model.input ++ String.fromChar c
                        , result = Err ""
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        GotStars result ->
            ( { model
                | loading = False
                , result =
                    case result of
                        Ok stars ->
                            Ok stars

                        Err _ ->
                            Err "Request failed"
              }
            , Effect.none
            )


fetchStars : String -> Effect.Effect Msg
fetchStars repo =
    BackendTask.Http.getJson
        ("https://api.github.com/repos/" ++ repo)
        (Decode.field "stargazers_count" Decode.int)
        |> BackendTask.allowFatal
        |> Effect.attempt GotStars


view : Tui.Context -> Model -> Tui.Screen.Screen
view _ model =
    let
        dimStyle =
            { plain | attributes = [ Tui.Screen.Dim ] }
    in
    Tui.Screen.lines
        [ Tui.Screen.text ""
        , Tui.Screen.styled { plain | fg = Just Ansi.Color.cyan, attributes = [ Tui.Screen.Bold ] }
            "  GitHub Stars Fetcher"
        , Tui.Screen.text ""
        , Tui.Screen.concat
            [ Tui.Screen.styled dimStyle "  Repo: "
            , Tui.Screen.styled { plain | attributes = [ Tui.Screen.Bold ] } model.input
            , Tui.Screen.styled dimStyle "▌"
            ]
        , Tui.Screen.text ""
        , case ( model.loading, model.result ) of
            ( True, _ ) ->
                Tui.Screen.styled { plain | fg = Just Ansi.Color.yellow } "  ⟳ Fetching..."

            ( _, Ok stars ) ->
                Tui.Screen.concat
                    [ Tui.Screen.text "  "
                    , Tui.Screen.styled { plain | fg = Just Ansi.Color.yellow } "★ "
                    , Tui.Screen.styled { plain | fg = Just Ansi.Color.green, attributes = [ Tui.Screen.Bold ] }
                        (String.fromInt stars)
                    , Tui.Screen.styled dimStyle
                        (" stars on " ++ model.input)
                    ]

            ( _, Err "" ) ->
                Tui.Screen.styled dimStyle "  Press Enter to fetch"

            ( _, Err errMsg ) ->
                Tui.Screen.styled { plain | fg = Just Ansi.Color.red }
                    ("  " ++ errMsg)
        , Tui.Screen.text ""
        , Tui.Screen.styled dimStyle "  Enter    fetch stars"
        , Tui.Screen.styled dimStyle "  Esc      quit"
        ]


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.onKeyPress KeyPressed
