module MiniGitTests exposing (stepper, suite)

import Ansi.Color
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Test.Runner
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Input as Input
import Tui.Keybinding as Keybinding
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
        , describe "help modal"
            [ test "? opens help modal" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Keybindings"
                        |> TuiTest.ensureViewHas "Esc: close"
                        |> TuiTest.expectRunning
            , test "help shows binding descriptions" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Quit"
                        |> TuiTest.ensureViewHas "Next commit"
                        |> TuiTest.expectRunning
            , test "escape closes help" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Keybindings"
                        |> TuiTest.pressKeyWith { key = Tui.Escape, modifiers = [] }
                        |> TuiTest.ensureViewDoesNotHave "Keybindings"
                        |> TuiTest.expectRunning
            , test "typing in help modal filters by description" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.pressKey 'u'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKey 't'
                        |> TuiTest.ensureViewHas "Quit"
                        |> TuiTest.ensureViewDoesNotHave "Next commit"
                        |> TuiTest.expectRunning
            , test "@ prefix filters by key name" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.pressKey '@'
                        |> TuiTest.pressKey 't'
                        |> TuiTest.pressKey 'a'
                        |> TuiTest.pressKey 'b'
                        |> TuiTest.ensureViewHas "Switch pane"
                        |> TuiTest.ensureViewDoesNotHave "Quit"
                        |> TuiTest.expectRunning
            ]
        , describe "keybinding dispatch"
            [ test "j navigates via keybinding dispatch" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
            , test "down arrow navigates as alternate key" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKeyWith { key = Tui.Arrow Tui.Down, modifiers = [] }
                        |> TuiTest.ensureViewHas "▸ def5678"
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
    , modal : Maybe ModalState
    , lastAction : String
    }


type ModalState
    = CommitModal { input : Input.State }
    | HelpModal { filter : Input.State }


type Action
    = DoNavigate Int
    | DoQuit
    | DoSwitchPane
    | DoOpenCommit
    | DoOpenHelp


type Msg
    = KeyPressed Tui.KeyEvent
    | Mouse Tui.MouseEvent
    | GotPaste String
    | SelectCommit Int


testGlobalBindings : Keybinding.Group Action
testGlobalBindings =
    Keybinding.group "Global"
        [ Keybinding.binding (Tui.Character 'q') "Quit" DoQuit
        , Keybinding.binding Tui.Tab "Switch pane" DoSwitchPane
        , Keybinding.binding (Tui.Character 'c') "Commit" DoOpenCommit
        , Keybinding.binding (Tui.Character '?') "Help" DoOpenHelp
        ]


testCommitBindings : Keybinding.Group Action
testCommitBindings =
    Keybinding.group "Commits"
        [ Keybinding.binding (Tui.Character 'j') "Next commit" (DoNavigate 1)
            |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
        , Keybinding.binding (Tui.Character 'k') "Previous commit" (DoNavigate -1)
            |> Keybinding.withAlternate (Tui.Arrow Tui.Up)
        ]


testActiveBindings : List (Keybinding.Group Action)
testActiveBindings =
    [ testCommitBindings, testGlobalBindings ]


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
    ( { layout = Layout.init |> Layout.focusPane "commits"
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
        Just (CommitModal modalState) ->
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
                            ( { model | modal = Just (CommitModal { input = Input.update event modalState.input }) }
                            , Effect.none
                            )

                GotPaste pastedText ->
                    ( { model | modal = Just (CommitModal { input = Input.insertText pastedText modalState.input }) }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        Just (HelpModal helpState) ->
            case msg of
                KeyPressed event ->
                    case event.key of
                        Tui.Escape ->
                            ( { model | modal = Nothing }, Effect.none )

                        _ ->
                            ( { model | modal = Just (HelpModal { filter = Input.update event helpState.filter }) }
                            , Effect.none
                            )

                GotPaste pastedText ->
                    ( { model | modal = Just (HelpModal { filter = Input.insertText pastedText helpState.filter }) }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        Nothing ->
            case msg of
                KeyPressed event ->
                    case Keybinding.dispatch testActiveBindings event of
                        Just action ->
                            handleAction action model

                        Nothing ->
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


handleAction : Action -> Model -> ( Model, Effect Msg )
handleAction action model =
    case action of
        DoNavigate direction ->
            ( { model
                | layout =
                    (if direction > 0 then
                        Layout.navigateDown "commits"

                     else
                        Layout.navigateUp "commits"
                    )
                        model.layout
              }
            , Effect.none
            )

        DoQuit ->
            ( model, Effect.exit )

        DoSwitchPane ->
            ( model, Effect.none )

        DoOpenCommit ->
            ( { model | modal = Just (CommitModal { input = Input.init "" }) }, Effect.none )

        DoOpenHelp ->
            ( { model | modal = Just (HelpModal { filter = Input.init "" }) }, Effect.none )


miniGitView : Tui.Context -> Model -> Tui.Screen
miniGitView ctx model =
    let
        layoutState =
            Layout.withContext { width = ctx.width, height = ctx.height } model.layout

        bgRows =
            Layout.toRows layoutState (miniGitLayout model)

        rows =
            case model.modal of
                Just (CommitModal modalState) ->
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

                Just (HelpModal helpState) ->
                    let
                        filterText =
                            Input.text helpState.filter

                        helpBody =
                            Keybinding.helpRows filterText testActiveBindings

                        filterRow =
                            Tui.concat
                                [ Tui.styled { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] } "Filter: "
                                , Input.view { width = 40 } helpState.filter
                                ]
                    in
                    Tui.Modal.overlay
                        { title = "Keybindings"
                        , body = filterRow :: Tui.text "" :: helpBody
                        , footer = "Esc: close │ @: filter by key"
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
