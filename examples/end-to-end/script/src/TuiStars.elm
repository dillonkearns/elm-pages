module TuiStars exposing (run)

{-| TUI demo: type a GitHub repo name, press Enter to fetch star count.

    elm - pages run script / src / TuiStars.elm

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import BackendTask.Http
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Pages.Script as Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Sub


type alias Model =
    { input : String
    , result : Result String Int
    , loading : Bool
    }


type Msg
    = KeyPressed Tui.KeyEvent
    | GotStars (Result FatalError Int)


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
                Tui.Escape ->
                    ( model, Effect.exit )

                Tui.Character 'q' ->
                    if List.member Tui.Ctrl event.modifiers then
                        ( model, Effect.exit )

                    else
                        ( { model
                            | input = model.input ++ "q"
                            , result = Err ""
                          }
                        , Effect.none
                        )

                Tui.Enter ->
                    ( { model | loading = True, result = Err "Loading..." }
                    , fetchStars model.input
                    )

                Tui.Backspace ->
                    ( { model
                        | input = String.dropRight 1 model.input
                        , result = Err ""
                      }
                    , Effect.none
                    )

                Tui.Character c ->
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


view : Tui.Context -> Model -> Tui.Screen
view _ model =
    let
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] }
    in
    Tui.lines
        [ Tui.text ""
        , Tui.styled { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.bold ] }
            "  GitHub Stars Fetcher"
        , Tui.text ""
        , Tui.concat
            [ Tui.styled dimStyle "  Repo: "
            , Tui.styled { fg = Nothing, bg = Nothing, attributes = [ Tui.bold ] } model.input
            , Tui.styled dimStyle "▌"
            ]
        , Tui.text ""
        , case ( model.loading, model.result ) of
            ( True, _ ) ->
                Tui.styled { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [] } "  ⟳ Fetching..."

            ( _, Ok stars ) ->
                Tui.concat
                    [ Tui.text "  "
                    , Tui.styled { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [] } "★ "
                    , Tui.styled { fg = Just Ansi.Color.green, bg = Nothing, attributes = [ Tui.bold ] }
                        (String.fromInt stars)
                    , Tui.styled dimStyle
                        (" stars on " ++ model.input)
                    ]

            ( _, Err "" ) ->
                Tui.styled dimStyle "  Press Enter to fetch"

            ( _, Err errMsg ) ->
                Tui.styled { fg = Just Ansi.Color.red, bg = Nothing, attributes = [] }
                    ("  " ++ errMsg)
        , Tui.text ""
        , Tui.styled dimStyle "  Enter    fetch stars"
        , Tui.styled dimStyle "  Esc      quit"
        ]


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.onKeyPress KeyPressed
