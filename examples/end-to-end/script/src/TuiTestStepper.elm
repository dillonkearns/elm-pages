module TuiTestStepper exposing (run)

{-| Interactive test stepper — step through a TUI test pipeline and see the
rendered screen at each step.

    elm - pages run script / src / TuiTestStepper.elm

Navigate with ← → arrow keys, q to quit.

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)
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
        sampleCommits : List MiniGitCommit
        sampleCommits =
            [ { sha = "abc1234", message = "Initial commit" }
            , { sha = "def5678", message = "Add feature X" }
            , { sha = "345cdef", message = "Fix bug in parser" }
            , { sha = "789abcd", message = "Update documentation" }
            , { sha = "aaa1111", message = "Refactor module structure" }
            , { sha = "bbb2222", message = "Add unit tests" }
            ]

        miniGitTest : TuiTest.TuiTest MiniGitModel MiniGitMsg
        miniGitTest =
            TuiTest.start
                { data = sampleCommits
                , init = miniGitInit
                , update = miniGitUpdate
                , view = miniGitView
                , subscriptions = miniGitSubscriptions
                }
    in
    miniGitTest
        |> TuiTest.withModelToString Debug.toString
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        |> TuiTest.click { row = 1, col = 5 }
        |> TuiTest.pressKey 'k'
        |> TuiTest.scrollDown { row = 3, col = 5 }
        |> TuiTest.scrollDown { row = 3, col = 5 }
        |> TuiTest.toSnapshots



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
            String.repeat (ctx.width - 4) "─"

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
            let
                renderedScreen : Tui.Screen
                renderedScreen =
                    snapshot.rerender { width = ctx.width - 6, height = ctx.height - 14 }
            in
            Tui.lines
                ([ Tui.styled headerStyle
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
                 ]
                    ++ (renderedScreen
                            |> Tui.toLines
                            |> List.map
                                (\line ->
                                    Tui.concat
                                        [ Tui.styled dimStyle "  │ "
                                        , Tui.text line
                                        ]
                                )
                       )
                    ++ [ Tui.text ""
                       , Tui.styled dimStyle ("  " ++ separator)
                       , case snapshot.modelState of
                            Just modelStr ->
                                Tui.lines
                                    [ Tui.text ""
                                    , Tui.styled
                                        { fg = Just Ansi.Color.green, bg = Nothing, attributes = [ Tui.bold ] }
                                        "  Model:"
                                    , modelStr
                                        |> String.lines
                                        |> List.map (\line -> Tui.styled dimStyle ("    " ++ line))
                                        |> Tui.lines
                                    ]

                            Nothing ->
                                Tui.empty
                       , Tui.text ""
                       , stepIndicator
                       , Tui.text ""
                       , Tui.styled dimStyle "  ← → navigate   q quit"
                       ]
                )

        Nothing ->
            Tui.styled dimStyle "  No snapshots"


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.onKeyPress KeyPressed



-- Inline MiniGit (same logic as MiniGitTests.elm)


type alias MiniGitCommit =
    { sha : String
    , message : String
    }


type alias MiniGitModel =
    { commits : List MiniGitCommit
    , selected : Int
    , scrollOffset : Int
    }


type MiniGitMsg
    = MiniGitKeyPressed Tui.KeyEvent
    | MiniGitMouse Tui.MouseEvent


miniGitInit : List MiniGitCommit -> ( MiniGitModel, Effect.Effect MiniGitMsg )
miniGitInit commits =
    ( { commits = commits
      , selected = 0
      , scrollOffset = 0
      }
    , Effect.none
    )


miniGitUpdate : MiniGitMsg -> MiniGitModel -> ( MiniGitModel, Effect.Effect MiniGitMsg )
miniGitUpdate msg model =
    let
        maxIndex : Int
        maxIndex =
            List.length model.commits - 1
    in
    case msg of
        MiniGitKeyPressed event ->
            case event.key of
                Tui.Character 'j' ->
                    ( adjustScroll { model | selected = min maxIndex (model.selected + 1) }, Effect.none )

                Tui.Character 'k' ->
                    ( adjustScroll { model | selected = max 0 (model.selected - 1) }, Effect.none )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )

        MiniGitMouse event ->
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


adjustScroll : MiniGitModel -> MiniGitModel
adjustScroll model =
    if model.selected < model.scrollOffset then
        { model | scrollOffset = model.selected }

    else if model.selected >= model.scrollOffset + 5 then
        { model | scrollOffset = model.selected - 4 }

    else
        model


miniGitView : Tui.Context -> MiniGitModel -> Tui.Screen
miniGitView _ model =
    let
        dimStyle : Tui.Style
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] }

        selectedCommit : Maybe MiniGitCommit
        selectedCommit =
            model.commits |> List.drop model.selected |> List.head
    in
    Tui.lines
        ([ Tui.styled { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.bold ] } "Mini Git Log"
         , Tui.text ""
         ]
            ++ (model.commits
                    |> List.indexedMap
                        (\i commit ->
                            Tui.concat
                                [ Tui.text
                                    (if i == model.selected then
                                        "▸ "

                                     else
                                        "  "
                                    )
                                , Tui.styled
                                    (if i == model.selected then
                                        { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [ Tui.bold ] }

                                     else
                                        dimStyle
                                    )
                                    commit.sha
                                , Tui.text (" " ++ commit.message)
                                ]
                        )
               )
            ++ [ Tui.text ""
               , case selectedCommit of
                    Just commit ->
                        Tui.lines
                            [ Tui.styled dimStyle "───────────"
                            , Tui.concat
                                [ Tui.styled dimStyle "SHA: "
                                , Tui.text commit.sha
                                ]
                            , Tui.text commit.message
                            ]

                    Nothing ->
                        Tui.empty
               ]
        )


miniGitSubscriptions : MiniGitModel -> Tui.Sub.Sub MiniGitMsg
miniGitSubscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress MiniGitKeyPressed
        , Tui.Sub.onMouse MiniGitMouse
        ]
