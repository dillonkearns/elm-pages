module MiniGitTests exposing (stepper, suite)

import Ansi.Color
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Test.Runner
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Input as Input
import Tui.Layout as Layout
import Tui.Modal
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
                                    [ \str -> str |> String.contains "╭" |> Expect.equal True
                                    , \str -> str |> String.contains "╮" |> Expect.equal True
                                    , \str -> str |> String.contains "╰" |> Expect.equal True
                                    , \str -> str |> String.contains "╯" |> Expect.equal True
                                    , \str -> str |> String.contains "┬" |> Expect.equal True
                                    , \str -> str |> String.contains "┴" |> Expect.equal True
                                    ]
                                    s
                            )
                        |> TuiTest.expectRunning
            ]
        , describe "commit dialog"
            [ test "c opens commit dialog" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.ensureViewHas "Commit"
                        |> TuiTest.ensureViewHas "Enter: confirm"
                        |> TuiTest.expectRunning
            , test "typing in commit dialog" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.pressKey 'f'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.ensureViewHas "fix"
                        |> TuiTest.expectRunning
            , test "escape dismisses commit dialog" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.ensureViewHas "Commit"
                        |> TuiTest.pressKeyWith { key = Tui.Escape, modifiers = [] }
                        |> TuiTest.ensureViewDoesNotHave "Enter: confirm"
                        |> TuiTest.expectRunning
            , test "enter confirms commit with typed message" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.pressKey 'h'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Committed: hi"
                        |> TuiTest.ensureViewDoesNotHave "Enter: confirm"
                        |> TuiTest.expectRunning
            , test "keys don't navigate while modal is open" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        -- j should type into input, not navigate commits
                        |> TuiTest.ensureViewHas "jjj"
                        |> TuiTest.ensureViewHas "▸ abc1234"
                        |> TuiTest.expectRunning
            ]
        , describe "bracketed paste"
            [ test "paste inserts text into commit dialog" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.paste "fix: resolve null pointer in parser"
                        |> TuiTest.ensureViewHas "fix: resolve null pointer"
                        |> TuiTest.expectRunning
            , test "paste after typing appends at cursor" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.pressKey 'A'
                        |> TuiTest.pressKey 'B'
                        |> TuiTest.paste "CD"
                        |> TuiTest.pressKey 'E'
                        |> TuiTest.ensureViewHas "ABCDE"
                        |> TuiTest.expectRunning
            , test "paste with enter confirms the pasted message" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.paste "docs: update README"
                        |> TuiTest.pressKeyWith { key = Tui.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Committed: docs: update README"
                        |> TuiTest.expectRunning
            , test "paste with newlines strips them for single-line input" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.paste "line one\nline two\nline three"
                        |> TuiTest.ensureViewHas "line one line two line three"
                        |> TuiTest.expectRunning
            , test "paste is ignored when no modal is open" <|
                \() ->
                    miniGitTest
                        |> TuiTest.paste "should be ignored"
                        |> TuiTest.ensureViewHas "▸ abc1234"
                        |> TuiTest.ensureViewDoesNotHave "should be ignored"
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
    , modal : Maybe { input : Input.State }
    , lastAction : String
    }


type Msg
    = KeyPressed Tui.KeyEvent
    | Mouse Tui.MouseEvent
    | GotPaste String
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
      , modal = Nothing
      , lastAction = ""
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
    case model.modal of
        Just modalState ->
            case msg of
                KeyPressed event ->
                    case event.key of
                        Tui.Escape ->
                            ( { model | modal = Nothing }, Effect.none )

                        Tui.Enter ->
                            let
                                commitMsg =
                                    Input.text modalState.input
                            in
                            ( { model
                                | modal = Nothing
                                , lastAction =
                                    if String.isEmpty commitMsg then
                                        "(empty commit message)"

                                    else
                                        "Committed: " ++ commitMsg
                              }
                            , Effect.none
                            )

                        _ ->
                            ( { model | modal = Just { input = Input.update event modalState.input } }
                            , Effect.none
                            )

                GotPaste pastedText ->
                    ( { model | modal = Just { input = Input.insertText pastedText modalState.input } }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        Nothing ->
            case msg of
                KeyPressed event ->
                    case event.key of
                        Tui.Character 'c' ->
                            ( { model | modal = Just { input = Input.init "" } }, Effect.none )

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
                            Layout.handleMouse mouseEvent { width = 80, height = 24 } (miniGitLayout model) model.layout
                    in
                    case maybeMsg of
                        Just userMsg ->
                            miniGitUpdate userMsg { model | layout = newLayout }

                        Nothing ->
                            ( { model | layout = newLayout }, Effect.none )

                _ ->
                    ( model, Effect.none )


miniGitView : Tui.Context -> Model -> Tui.Screen
miniGitView ctx model =
    let
        layoutState =
            Layout.withContext { width = ctx.width, height = ctx.height } model.layout

        bgRows =
            Layout.toRows layoutState (miniGitLayout model)

        rows =
            case model.modal of
                Just modalState ->
                    Tui.Modal.overlay
                        { title = "Commit"
                        , body =
                            [ Tui.text ""
                            , Input.view { width = 40 } modalState.input
                            , Tui.text ""
                            ]
                        , footer = "Enter: confirm │ Esc: cancel"
                        , width = 50
                        }
                        { termWidth = ctx.width, termHeight = ctx.height }
                        bgRows

                Nothing ->
                    bgRows
    in
    Tui.lines
        (if String.isEmpty model.lastAction then
            rows

         else
            -- Replace last row with status
            List.take (List.length rows - 1) rows ++ [ Tui.text (" " ++ model.lastAction) ]
        )


miniGitSubscriptions : Model -> Tui.Sub.Sub Msg
miniGitSubscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse Mouse
        , Tui.Sub.onPaste GotPaste
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
