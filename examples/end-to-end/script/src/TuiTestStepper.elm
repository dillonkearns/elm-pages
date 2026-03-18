module TuiTestStepper exposing (run, stepper)

{-| TUI test with interactive stepper support.

Run as a script:
elm-pages run script/src/TuiTestStepper.elm

Run through the interactive stepper:
elm-pages test script/src/TuiTestStepper.elm

-}

import Ansi.Color
import Pages.Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Sub
import Tui.Test as TuiTest
import Tui.Test.Stepper


{-| The test pipeline — shared between unit tests and the stepper.
-}
stepper : TuiTest.TuiTest Model Msg
stepper =
    TuiTest.startWithContext { width = 60, height = 12, colorProfile = Tui.TrueColor }
        { data = sampleCommits
        , init = miniGitInit
        , update = miniGitUpdate
        , view = miniGitView
        , subscriptions = miniGitSubscriptions
        }
        |> TuiTest.withModelToString Debug.toString
        -- Navigate down through visible commits
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        -- Past the 5-row window — viewport scrolls, new commits appear
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        -- Scroll back up
        |> TuiTest.pressKey 'k'
        |> TuiTest.pressKey 'k'
        |> TuiTest.pressKey 'k'
        -- Click on a visible commit
        |> TuiTest.click { row = 3, col = 5 }


{-| Run the stepper as a script (for elm-pages run).
-}
run : Script
run =
    Tui.Test.Stepper.run stepper



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
    = KeyPressed Tui.KeyEvent
    | Mouse Tui.MouseEvent


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
                Tui.Character 'j' ->
                    ( adjustScroll { model | selected = min maxIndex (model.selected + 1) }, Effect.none )

                Tui.Character 'k' ->
                    ( adjustScroll { model | selected = max 0 (model.selected - 1) }, Effect.none )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )

        Mouse event ->
            case event of
                Tui.Click { row } ->
                    let
                        clickedIndex : Int
                        clickedIndex =
                            row - 2 + model.scrollOffset
                    in
                    if clickedIndex >= 0 && clickedIndex <= maxIndex then
                        ( { model | selected = clickedIndex }, Effect.none )

                    else
                        ( model, Effect.none )

                Tui.ScrollUp _ ->
                    ( adjustScroll { model | selected = max 0 (model.selected - 1) }, Effect.none )

                Tui.ScrollDown _ ->
                    ( adjustScroll { model | selected = min maxIndex (model.selected + 1) }, Effect.none )


adjustScroll : Model -> Model
adjustScroll model =
    if model.selected < model.scrollOffset then
        { model | scrollOffset = model.selected }

    else if model.selected >= model.scrollOffset + 5 then
        { model | scrollOffset = model.selected - 4 }

    else
        model


miniGitView : Tui.Context -> Model -> Tui.Screen
miniGitView ctx model =
    let
        dimStyle : Tui.Style
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.Dim ] }

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
    Tui.lines
        ([ Tui.styled { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.Bold ] } "Mini Git Log"
         , Tui.text ""
         ]
            ++ List.map
                (\( i, commit ) ->
                    Tui.concat
                        [ Tui.text
                            (if i == model.selected then
                                "▸ "

                             else
                                "  "
                            )
                        , Tui.styled
                            (if i == model.selected then
                                { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [ Tui.Bold ] }

                             else
                                dimStyle
                            )
                            commit.sha
                        , Tui.text (" " ++ commit.message)
                        ]
                )
                visibleCommits
            ++ [ Tui.text ""
               , case model.commits |> List.drop model.selected |> List.head of
                    Just commit ->
                        Tui.lines
                            [ Tui.styled dimStyle "───────────"
                            , Tui.concat [ Tui.styled dimStyle "SHA: ", Tui.text commit.sha ]
                            , Tui.text commit.message
                            ]

                    Nothing ->
                        Tui.empty
               ]
        )


miniGitSubscriptions : Model -> Tui.Sub.Sub Msg
miniGitSubscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse Mouse
        ]
