module MiniGitTests exposing (stepper, suite)

import Ansi.Color
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Test.Runner
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Layout as Layout
import Tui.Sub
import Tui.Test as TuiTest


suite : Test
suite =
    describe "MiniGit"
        [ describe "keyboard navigation"
            [ test "initial view shows commit list with first selected" <|
                \() ->
                    miniGitTest
                        |> TuiTest.ensureViewHas "▸ abc1234"
                        |> TuiTest.ensureViewHas "def5678"
                        |> TuiTest.expectRunning
            , test "j moves selection down" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
            , test "k moves selection up" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.ensureViewHas "▸ abc1234"
                        |> TuiTest.expectRunning
            , test "q exits" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.expectExit
            ]
        , describe "mouse interactions"
            [ test "clicking on a commit selects it (coordinates)" <|
                \() ->
                    miniGitTest
                        |> TuiTest.click { row = 2, col = 5 }
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
            , test "clickText finds and clicks by content" <|
                \() ->
                    miniGitTest
                        |> TuiTest.clickText "345cdef"
                        |> TuiTest.ensureViewHas "▸ 345cdef"
                        |> TuiTest.expectRunning
            , test "clickText on last item" <|
                \() ->
                    miniGitTest
                        |> TuiTest.clickText "bbb2222"
                        |> TuiTest.ensureViewHas "▸ bbb2222"
                        |> TuiTest.expectRunning
            , test "clickText fails with helpful message when text not found" <|
                \() ->
                    miniGitTest
                        |> TuiTest.clickText "nonexistent"
                        |> TuiTest.expectRunning
                        |> expectFailureContaining "nonexistent"
            , test "scroll down moves viewport" <|
                \() ->
                    miniGitTest
                        |> TuiTest.scrollDown { row = 2, col = 5 }
                        |> TuiTest.expectRunning
            ]
        , describe "Layout.resetScroll"
            [ test "resetScroll sets scroll to 0" <|
                \() ->
                    let
                        state : Layout.State
                        state =
                            Layout.init
                                |> Layout.navigateDown "list"
                                |> Layout.navigateDown "list"
                                |> Layout.resetScroll "list"
                    in
                    Layout.scrollPosition "list" state
                        |> Expect.equal 0
            ]
        , describe "layout"
            [ test "shows pane titles" <|
                \() ->
                    miniGitTest
                        |> TuiTest.ensureViewHas "Commits"
                        |> TuiTest.ensureViewHas "Diff"
                        |> TuiTest.expectRunning
            , test "shows box borders" <|
                \() ->
                    miniGitTest
                        |> TuiTest.ensureView
                            (\s ->
                                Expect.all
                                    [ \str -> str |> String.contains "┌" |> Expect.equal True
                                    , \str -> str |> String.contains "┐" |> Expect.equal True
                                    , \str -> str |> String.contains "└" |> Expect.equal True
                                    , \str -> str |> String.contains "┘" |> Expect.equal True
                                    , \str -> str |> String.contains "┬" |> Expect.equal True
                                    , \str -> str |> String.contains "┴" |> Expect.equal True
                                    ]
                                    s
                            )
                        |> TuiTest.expectRunning
            ]
        , describe "snapshots"
            [ test "model state shows layout changes" <|
                \() ->
                    miniGitTest
                        |> TuiTest.withModelToString Debug.toString
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.toSnapshots
                        |> List.drop 1
                        |> List.head
                        |> Maybe.andThen .modelState
                        |> Maybe.withDefault ""
                        |> String.contains "layout"
                        |> Expect.equal True
            ]
        ]


{-| Assert an Expectation is a failure containing the given text.
-}
expectFailureContaining : String -> Expectation -> Expectation
expectFailureContaining needle expectation =
    case Test.Runner.getFailureReason expectation of
        Nothing ->
            Expect.fail
                ("Expected a failure containing \""
                    ++ needle
                    ++ "\" but the test passed."
                )

        Just { description } ->
            if String.contains needle description then
                Expect.pass

            else
                Expect.fail
                    ("Expected failure to contain \""
                        ++ needle
                        ++ "\" but was: \""
                        ++ description
                        ++ "\""
                    )



-- Stepper for elm-pages test


stepper : TuiTest.TuiTest Model Msg
stepper =
    miniGitTest
        |> TuiTest.withModelToString Debug.toString
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'j'
        |> TuiTest.pressKey 'k'
        |> TuiTest.click { row = 2, col = 5 }



-- Inline MiniGit using Layout


type alias Commit =
    { sha : String
    , message : String
    }


type alias Model =
    { layout : Layout.State
    , commits : List Commit
    }


type Msg
    = KeyPressed Tui.KeyEvent
    | Mouse Tui.MouseEvent
    | SelectCommit Int


sampleCommits : List Commit
sampleCommits =
    [ { sha = "abc1234", message = "Initial commit" }
    , { sha = "def5678", message = "Add feature" }
    , { sha = "345cdef", message = "Fix bug" }
    , { sha = "789abcd", message = "Update docs" }
    , { sha = "aaa1111", message = "Refactor" }
    , { sha = "bbb2222", message = "Add tests" }
    ]


miniGitInit : List Commit -> ( Model, Effect Msg )
miniGitInit commits =
    ( { layout = Layout.init
      , commits = commits
      }
    , Effect.none
    )


miniGitLayout : Model -> Layout.Layout Msg
miniGitLayout model =
    Layout.horizontal
        [ Layout.pane "commits"
            { title = "Commits", width = Layout.fill }
            (Layout.selectableList
                { onSelect = SelectCommit
                , selected =
                    \commit ->
                        Tui.styled
                            { fg = Just Ansi.Color.yellow
                            , bg = Nothing
                            , attributes = [ Tui.bold ]
                            }
                            ("▸ " ++ commit.sha ++ " " ++ commit.message)
                , default =
                    \commit ->
                        Tui.text ("  " ++ commit.sha ++ " " ++ commit.message)
                }
                model.commits
            )
        , Layout.pane "diff"
            { title = "Diff", width = Layout.fillPortion 2 }
            (Layout.content [ Tui.text "(diff placeholder)" ])
        ]


miniGitUpdate : Msg -> Model -> ( Model, Effect Msg )
miniGitUpdate msg model =
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Character 'j' ->
                    ( { model | layout = Layout.navigateDown "commits" model.layout }
                    , Effect.none
                    )

                Tui.Character 'k' ->
                    ( { model | layout = Layout.navigateUp "commits" model.layout }
                    , Effect.none
                    )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )

        Mouse mouseEvent ->
            let
                ( newLayout, maybeMsg ) =
                    Layout.handleMouse mouseEvent (miniGitLayout model) model.layout
            in
            case maybeMsg of
                Just userMsg ->
                    miniGitUpdate userMsg { model | layout = newLayout }

                Nothing ->
                    ( { model | layout = newLayout }, Effect.none )

        SelectCommit _ ->
            ( model, Effect.none )


miniGitView : Tui.Context -> Model -> Tui.Screen
miniGitView ctx model =
    miniGitLayout model
        |> Layout.toScreen (Layout.withContext { width = ctx.width, height = ctx.height } model.layout)


miniGitSubscriptions : Model -> Tui.Sub.Sub Msg
miniGitSubscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse Mouse
        ]


miniGitTest : TuiTest.TuiTest Model Msg
miniGitTest =
    TuiTest.start
        { data = sampleCommits
        , init = miniGitInit
        , update = miniGitUpdate
        , view = miniGitView
        , subscriptions = miniGitSubscriptions
        }
