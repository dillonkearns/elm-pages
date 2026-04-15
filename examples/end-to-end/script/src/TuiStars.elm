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
import Tui exposing (plain)
import Tui.Effect as Effect
import Tui.Program
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
    Tui.Program.program
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
            { plain | attributes = [ Tui.Dim ] }
    in
    Tui.lines
        [ Tui.text ""
        , Tui.styled { plain | fg = Just Ansi.Color.cyan, attributes = [ Tui.Bold ] }
            "  GitHub Stars Fetcher"
        , Tui.text ""
        , Tui.concat
            [ Tui.styled dimStyle "  Repo: "
            , Tui.styled { plain | attributes = [ Tui.Bold ] } model.input
            , Tui.styled dimStyle "▌"
            ]
        , Tui.text ""
        , case ( model.loading, model.result ) of
            ( True, _ ) ->
                Tui.styled { plain | fg = Just Ansi.Color.yellow } "  ⟳ Fetching..."

            ( _, Ok stars ) ->
                Tui.concat
                    [ Tui.text "  "
                    , Tui.styled { plain | fg = Just Ansi.Color.yellow } "★ "
                    , Tui.styled { plain | fg = Just Ansi.Color.green, attributes = [ Tui.Bold ] }
                        (String.fromInt stars)
                    , Tui.styled dimStyle
                        (" stars on " ++ model.input)
                    ]

            ( _, Err "" ) ->
                Tui.styled dimStyle "  Press Enter to fetch"

            ( _, Err errMsg ) ->
                Tui.styled { plain | fg = Just Ansi.Color.red }
                    ("  " ++ errMsg)
        , Tui.text ""
        , Tui.styled dimStyle "  Enter    fetch stars"
        , Tui.styled dimStyle "  Esc      quit"
        ]


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.onKeyPress KeyPressed
