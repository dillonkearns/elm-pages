module TuiTestStepper exposing (run)

{-| Interactive test stepper — step through a TUI test pipeline and see the
rendered screen at each step.

    elm - pages run script / src / TuiTestStepper.elm

Navigate with ← → arrow keys, q to quit.

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import BackendTask.Http
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Script as Script exposing (Script)
import Test.BackendTask as BackendTaskTest
import Tui
import Tui.Effect as Effect
import Tui.Sub
import Tui.Test as TuiTest


run : Script
run =
    Script.tui
        { data = BackendTask.succeed ()
        , init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- The demo test pipeline we're stepping through


demoSnapshots : List TuiTest.Snapshot
demoSnapshots =
    let
        starsTest : TuiTest.TuiTest StarsModel StarsMsg
        starsTest =
            TuiTest.start
                { data = ()
                , init = starsInit
                , update = starsUpdate
                , view = starsView
                , subscriptions = starsSubscriptions
                }
    in
    starsTest
        -- Edit: delete "elm-pages" (9 chars) and type "elm-graphql"
        |> repeatN 9 (TuiTest.pressKeyWith { key = Tui.Backspace, modifiers = [] })
        |> typeChars "elm-graphql"
        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
        |> TuiTest.resolveEffect
            (BackendTaskTest.simulateHttpGet
                "https://api.github.com/repos/dillonkearns/elm-graphql"
                (Encode.object [ ( "stargazers_count", Encode.int 780 ) ])
            )
        |> TuiTest.toSnapshots


repeatN : Int -> (a -> a) -> a -> a
repeatN n f val =
    if n <= 0 then
        val

    else
        repeatN (n - 1) f (f val)


typeChars : String -> TuiTest.TuiTest model msg -> TuiTest.TuiTest model msg
typeChars str tuiTest =
    String.foldl (\c acc -> TuiTest.pressKey c acc) tuiTest str



-- Stepper model


type alias Model =
    { snapshots : List TuiTest.Snapshot
    , currentIndex : Int
    }


type Msg
    = KeyPressed Tui.KeyEvent


init : () -> ( Model, Effect.Effect Msg )
init () =
    ( { snapshots = demoSnapshots
      , currentIndex = 0
      }
    , Effect.none
    )


update : Msg -> Model -> ( Model, Effect.Effect Msg )
update msg model =
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Arrow Tui.Right ->
                    ( { model
                        | currentIndex =
                            min (List.length model.snapshots - 1) (model.currentIndex + 1)
                      }
                    , Effect.none
                    )

                Tui.Arrow Tui.Left ->
                    ( { model
                        | currentIndex = max 0 (model.currentIndex - 1)
                      }
                    , Effect.none
                    )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )


view : Tui.Context -> Model -> Tui.Screen
view ctx model =
    let
        maybeSnapshot : Maybe TuiTest.Snapshot
        maybeSnapshot =
            model.snapshots
                |> List.drop model.currentIndex
                |> List.head

        dimStyle : Tui.Style
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] }

        headerStyle : Tui.Style
        headerStyle =
            { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.bold ] }

        separator : String
        separator =
            String.repeat ctx.width "─"

        stepIndicator : Tui.Screen
        stepIndicator =
            Tui.concat
                (model.snapshots
                    |> List.indexedMap
                        (\i snapshot ->
                            if i == model.currentIndex then
                                Tui.styled
                                    { fg = Just Ansi.Color.cyan
                                    , bg = Nothing
                                    , attributes = [ Tui.bold ]
                                    }
                                    (" ● " ++ snapshot.label ++ " ")

                            else
                                Tui.styled dimStyle " ○ "
                        )
                )
    in
    case maybeSnapshot of
        Just snapshot ->
            Tui.lines
                [ Tui.styled headerStyle
                    ("  Test Stepper — Step "
                        ++ String.fromInt (model.currentIndex + 1)
                        ++ " of "
                        ++ String.fromInt (List.length model.snapshots)
                    )
                , Tui.text ""
                , Tui.concat
                    [ Tui.styled dimStyle "  Action: "
                    , Tui.styled
                        { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [ Tui.bold ] }
                        snapshot.label
                    , if snapshot.hasPendingEffects then
                        Tui.styled
                            { fg = Just Ansi.Color.magenta, bg = Nothing, attributes = [] }
                            "  ⟳ pending effect"

                      else
                        Tui.empty
                    ]
                , Tui.text ""
                , Tui.styled dimStyle ("  " ++ separator)
                , Tui.text ""
                , -- Render the actual screen content indented
                  snapshot.screen
                    |> String.lines
                    |> List.map (\line -> Tui.text ("  │ " ++ line))
                    |> Tui.lines
                , Tui.text ""
                , Tui.styled dimStyle ("  " ++ separator)
                , Tui.text ""
                , stepIndicator
                , Tui.text ""
                , Tui.styled dimStyle "  ← → navigate   q quit"
                ]

        Nothing ->
            Tui.styled dimStyle "  No snapshots"


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.onKeyPress KeyPressed



-- Inline Stars TUI (same as test)


type alias StarsModel =
    { input : String
    , result : Result String Int
    , loading : Bool
    }


type StarsMsg
    = StarsKeyPressed Tui.KeyEvent
    | GotStars (Result FatalError Int)


starsInit : () -> ( StarsModel, Effect.Effect StarsMsg )
starsInit () =
    ( { input = "dillonkearns/elm-pages"
      , result = Err ""
      , loading = False
      }
    , Effect.none
    )


starsUpdate : StarsMsg -> StarsModel -> ( StarsModel, Effect.Effect StarsMsg )
starsUpdate msg model =
    case msg of
        StarsKeyPressed event ->
            case event.key of
                Tui.Escape ->
                    ( model, Effect.exit )

                Tui.Enter ->
                    ( { model | loading = True, result = Err "Loading..." }
                    , BackendTask.Http.getJson
                        ("https://api.github.com/repos/" ++ model.input)
                        (Decode.field "stargazers_count" Decode.int)
                        |> BackendTask.allowFatal
                        |> Effect.attempt GotStars
                    )

                Tui.Backspace ->
                    ( { model | input = String.dropRight 1 model.input, result = Err "" }
                    , Effect.none
                    )

                Tui.Character c ->
                    ( { model | input = model.input ++ String.fromChar c, result = Err "" }
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


starsView : Tui.Context -> StarsModel -> Tui.Screen
starsView _ model =
    let
        dimStyle : Tui.Style
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] }
    in
    Tui.lines
        [ Tui.styled { fg = Nothing, bg = Nothing, attributes = [ Tui.bold ] } "GitHub Stars"
        , Tui.concat
            [ Tui.text "Repo: "
            , Tui.text model.input
            ]
        , case ( model.loading, model.result ) of
            ( True, _ ) ->
                Tui.text "Loading..."

            ( _, Ok stars ) ->
                Tui.text ("Stars: " ++ String.fromInt stars)

            ( _, Err "" ) ->
                Tui.styled dimStyle "Press Enter to fetch"

            ( _, Err errMsg ) ->
                Tui.text errMsg
        ]


starsSubscriptions : StarsModel -> Tui.Sub.Sub StarsMsg
starsSubscriptions _ =
    Tui.Sub.onKeyPress StarsKeyPressed
