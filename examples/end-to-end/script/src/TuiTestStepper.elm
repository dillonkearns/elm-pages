module TuiTestStepper exposing (tuiTests)

{-| TUI test with named scenarios for `elm-pages test`.
-}

import Ansi.Color
import Tui
import Tui.Effect as Effect
import Tui.Event
import Tui.Screen exposing (plain)
import Tui.Sub
import Tui.Test as TuiTest


tuiTests : TuiTest.Test
tuiTests =
    TuiTest.describe "Mini Git"
        [ TuiTest.test "navigates and clicks through commits"
            (TuiTest.startWithContext { width = 60, height = 12, colorProfile = Tui.TrueColor }
                { data = sampleCommits
                , init = miniGitInit
                , update = miniGitUpdate
                , view = miniGitView
                , subscriptions = miniGitSubscriptions
                }
                |> TuiTest.withModelToString Debug.toString
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'k'
                |> TuiTest.pressKey 'k'
                |> TuiTest.pressKey 'k'
                |> TuiTest.click { row = 3, col = 5 }
                |> TuiTest.expectRunning
            )
        ]



-- Inline MiniGit


type alias Commit =
    { sha : String
    , message : String
    }


type alias Model =
    { commits : List Commit
    , selected : Int
    , scrollOffset : Int
    }


type Msg
    = KeyPressed Tui.Event.KeyEvent
    | Mouse Tui.Event.MouseEvent


sampleCommits : List Commit
sampleCommits =
    [ { sha = "abc1234", message = "Initial commit" }
    , { sha = "def5678", message = "Add feature X" }
    , { sha = "345cdef", message = "Fix bug in parser" }
    , { sha = "789abcd", message = "Update documentation" }
    , { sha = "aaa1111", message = "Refactor module structure" }
    , { sha = "bbb2222", message = "Add unit tests" }
    , { sha = "ccc3333", message = "Improve error handling" }
    , { sha = "ddd4444", message = "Add CLI options" }
    , { sha = "eee5555", message = "Fix memory leak" }
    , { sha = "fff6666", message = "Update dependencies" }
    , { sha = "aab7777", message = "Add TUI framework" }
    , { sha = "bbc8888", message = "Mouse support" }
    ]


miniGitInit : List Commit -> ( Model, Effect.Effect Msg )
miniGitInit commits =
    ( { commits = commits, selected = 0, scrollOffset = 0 }, Effect.none )


miniGitUpdate : Msg -> Model -> ( Model, Effect.Effect Msg )
miniGitUpdate msg model =
    let
        maxIndex : Int
        maxIndex =
            List.length model.commits - 1
    in
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Event.Character 'j' ->
                    ( adjustScroll { model | selected = min maxIndex (model.selected + 1) }, Effect.none )

                Tui.Event.Character 'k' ->
                    ( adjustScroll { model | selected = max 0 (model.selected - 1) }, Effect.none )

                Tui.Event.Character 'q' ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )

        Mouse event ->
            case event of
                Tui.Event.Click { row } ->
                    let
                        clickedIndex : Int
                        clickedIndex =
                            row - 2 + model.scrollOffset
                    in
                    if clickedIndex >= 0 && clickedIndex <= maxIndex then
                        ( { model | selected = clickedIndex }, Effect.none )

                    else
                        ( model, Effect.none )

                Tui.Event.ScrollUp _ ->
                    ( adjustScroll { model | selected = max 0 (model.selected - 1) }, Effect.none )

                Tui.Event.ScrollDown _ ->
                    ( adjustScroll { model | selected = min maxIndex (model.selected + 1) }, Effect.none )


adjustScroll : Model -> Model
adjustScroll model =
    if model.selected < model.scrollOffset then
        { model | scrollOffset = model.selected }

    else if model.selected >= model.scrollOffset + 5 then
        { model | scrollOffset = model.selected - 4 }

    else
        model


miniGitView : Tui.Context -> Model -> Tui.Screen.Screen
miniGitView ctx model =
    let
        dimStyle : Tui.Screen.Style
        dimStyle =
            { plain | attributes = [ Tui.Screen.Dim ] }

        visibleRows : Int
        visibleRows =
            max 3 (ctx.height - 7)

        visibleCommits : List ( Int, Commit )
        visibleCommits =
            model.commits
                |> List.indexedMap Tuple.pair
                |> List.drop model.scrollOffset
                |> List.take visibleRows
    in
    Tui.Screen.lines
        ([ Tui.Screen.styled { plain | fg = Just Ansi.Color.cyan, attributes = [ Tui.Screen.Bold ] } "Mini Git Log"
         , Tui.Screen.text ""
         ]
            ++ List.map
                (\( i, commit ) ->
                    Tui.Screen.concat
                        [ Tui.Screen.text
                            (if i == model.selected then
                                "▸ "

                             else
                                "  "
                            )
                        , Tui.Screen.styled
                            (if i == model.selected then
                                { plain | fg = Just Ansi.Color.yellow, attributes = [ Tui.Screen.Bold ] }

                             else
                                dimStyle
                            )
                            commit.sha
                        , Tui.Screen.text (" " ++ commit.message)
                        ]
                )
                visibleCommits
            ++ [ Tui.Screen.text ""
               , case model.commits |> List.drop model.selected |> List.head of
                    Just commit ->
                        Tui.Screen.lines
                            [ Tui.Screen.styled dimStyle "───────────"
                            , Tui.Screen.concat [ Tui.Screen.styled dimStyle "SHA: ", Tui.Screen.text commit.sha ]
                            , Tui.Screen.text commit.message
                            ]

                    Nothing ->
                        Tui.Screen.empty
               ]
        )


miniGitSubscriptions : Model -> Tui.Sub.Sub Msg
miniGitSubscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse Mouse
        ]
