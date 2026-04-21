module TuiStars exposing (app, run)

{-| TUI demo: edit a GitHub repo name, press Enter to fetch star count.

```sh
cd examples/end-to-end/script
npx --prefix .. elm-pages run src/TuiStars.elm
```

Starts with `dillonkearns/elm-pages` loaded into the input.

-}

import Ansi.Color
import BackendTask
import BackendTask.File
import BackendTask.Http
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Pages.Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Input as Input
import Tui.Screen exposing (plain)
import Tui.Sub


type alias Model =
    { repo : Input.State
    , result : Result String Int
    , loading : Bool
    }


type Msg
    = KeyPressed Tui.Sub.KeyEvent
    | RepoPasted String
    | GotStars (Result FatalError Int)


app : Tui.ProgramConfig String Model Msg
app =
    { data =
        BackendTask.File.rawFile "elm.json"
            |> BackendTask.allowFatal
            |> BackendTask.map (\_ -> "dillonkearns/elm-pages")
    , init = init
    , update = update
    , view = view
    , subscriptions = subscriptions
    }


run : Script
run =
    Tui.program app |> Tui.toScript


init : String -> ( Model, Effect.Effect Msg )
init initialRepo =
    ( { repo = Input.init initialRepo
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
                Tui.Sub.Escape ->
                    ( model, Effect.exit )

                Tui.Sub.Enter ->
                    ( { model | loading = True, result = Err "Loading..." }
                    , fetchStars (Input.text model.repo)
                    )

                _ ->
                    let
                        updatedRepo : Input.State
                        updatedRepo =
                            Input.update event model.repo
                    in
                    ( { model
                        | repo = updatedRepo
                        , result =
                            if Input.text updatedRepo /= Input.text model.repo then
                                Err ""

                            else
                                model.result
                      }
                    , Effect.none
                    )

        RepoPasted pastedRepo ->
            ( { model
                | repo = Input.insertText pastedRepo model.repo
                , result = Err ""
              }
            , Effect.none
            )

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
view ctx model =
    let
        dimStyle : Tui.Screen.Style
        dimStyle =
            { plain | attributes = [ Tui.Screen.Dim ] }

        repoText : String
        repoText =
            Input.text model.repo
    in
    Tui.Screen.lines
        [ Tui.Screen.text ""
        , Tui.Screen.styled { plain | fg = Just Ansi.Color.cyan, attributes = [ Tui.Screen.Bold ] }
            "  GitHub Stars Fetcher"
        , Tui.Screen.text ""
        , Tui.Screen.concat
            [ Tui.Screen.styled dimStyle "  Repo: "
            , Input.view { width = max 12 (ctx.width - 8) } model.repo
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
                        (" stars on " ++ repoText)
                    ]

            ( _, Err "" ) ->
                Tui.Screen.styled dimStyle "  Press Enter to fetch"

            ( _, Err errMsg ) ->
                Tui.Screen.styled { plain | fg = Just Ansi.Color.red }
                    ("  " ++ errMsg)
        , Tui.Screen.text ""
        , Tui.Screen.styled dimStyle "  Enter    fetch stars"
        , Tui.Screen.styled dimStyle "  Paste    insert repo"
        , Tui.Screen.styled dimStyle "  Esc      quit"
        ]


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onPaste RepoPasted
        ]
