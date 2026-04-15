module MiniGitTests exposing (suite, tuiTests)

import Ansi.Color
import Expect exposing (Expectation)
import Test exposing (Test, describe, test)
import Test.Runner
import Tui
import Tui.Layout.Effect as Effect exposing (Effect)
import Tui.Event
import Tui.Input as Input
import Tui.Keybinding as Keybinding
import Tui.Layout as Layout
import Tui.Modal
import Tui.Screen exposing (plain)
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
                        |> TuiTest.done
            , test "j moves selection down" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "k moves selection up" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.ensureViewHas "▸ abc1234"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "q exits" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.expectExit
                        |> TuiTest.done
            ]
        , describe "mouse interactions"
            [ test "clicking on a commit selects it (coordinates)" <|
                \() ->
                    miniGitTest
                        |> TuiTest.click { row = 2, col = 5 }
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "clickText finds and clicks by content" <|
                \() ->
                    miniGitTest
                        |> TuiTest.clickText "345cdef"
                        |> TuiTest.ensureViewHas "▸ 345cdef"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "clickText on last item" <|
                \() ->
                    miniGitTest
                        |> TuiTest.clickText "bbb2222"
                        |> TuiTest.ensureViewHas "▸ bbb2222"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "clickText fails with helpful message when text not found" <|
                \() ->
                    miniGitTest
                        |> TuiTest.clickText "nonexistent"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
                        |> expectFailureContaining "nonexistent"
            , test "scroll down moves viewport" <|
                \() ->
                    miniGitTest
                        |> TuiTest.scrollDown { row = 2, col = 5 }
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "Layout.resetScroll"
            [ test "resetScroll sets scroll to 0" <|
                \() ->
                    let
                        ( state, _ ) =
                            Layout.navigateDown "list"
                                (miniGitLayout { layout = Layout.init |> Layout.withContext { width = 80, height = 24 }, commits = sampleCommits, diffContent = "", modal = Nothing, lastAction = "" })
                                (Layout.init |> Layout.withContext { width = 80, height = 24 })
                    in
                    Layout.scrollPosition "list" (Layout.resetScroll "list" state)
                        |> Expect.equal 0
            ]
        , describe "layout"
            [ test "shows pane titles" <|
                \() ->
                    miniGitTest
                        |> TuiTest.ensureViewHas "Commits"
                        |> TuiTest.ensureViewHas "Diff"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "shows box borders" <|
                \() ->
                    miniGitTest
                        |> TuiTest.ensureViewHas "╭"
                        |> TuiTest.ensureViewHas "╮"
                        |> TuiTest.ensureViewHas "│"
                        |> TuiTest.ensureViewHas "─"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "commit dialog"
            [ test "c opens commit dialog" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.ensureViewHas "Commit"
                        |> TuiTest.ensureViewHas "Enter: confirm"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "typing in commit dialog" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.pressKey 'f'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.ensureViewHas "fix"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "escape dismisses commit dialog" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.ensureViewHas "Commit"
                        |> TuiTest.pressKeyWith { key = Tui.Event.Escape, modifiers = [] }
                        |> TuiTest.ensureViewDoesNotHave "Enter: confirm"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "enter confirms commit with typed message" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.pressKey 'h'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKeyWith { key = Tui.Event.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Committed: hi"
                        |> TuiTest.ensureViewDoesNotHave "Enter: confirm"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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
                        |> TuiTest.done
            ]
        , describe "bracketed paste"
            [ test "paste inserts text into commit dialog" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.paste "fix: resolve null pointer in parser"
                        |> TuiTest.ensureViewHas "fix: resolve null pointer"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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
                        |> TuiTest.done
            , test "paste with enter confirms the pasted message" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.paste "docs: update README"
                        |> TuiTest.pressKeyWith { key = Tui.Event.Enter, modifiers = [] }
                        |> TuiTest.ensureViewHas "Committed: docs: update README"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "paste with newlines strips them for single-line input" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.paste "line one\nline two\nline three"
                        |> TuiTest.ensureViewHas "line one line two line three"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "paste is ignored when no modal is open" <|
                \() ->
                    miniGitTest
                        |> TuiTest.paste "should be ignored"
                        |> TuiTest.ensureViewHas "▸ abc1234"
                        |> TuiTest.ensureViewDoesNotHave "should be ignored"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "help modal"
            [ test "? opens help modal" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Keybindings"
                        |> TuiTest.ensureViewHas "Esc: close"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "help shows binding descriptions" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Quit"
                        |> TuiTest.ensureViewHas "Next commit"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "escape closes help" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Keybindings"
                        |> TuiTest.pressKeyWith { key = Tui.Event.Escape, modifiers = [] }
                        |> TuiTest.ensureViewDoesNotHave "Keybindings"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "/ enters search mode, typing filters by description" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.pressKey '/'
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.pressKey 'u'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKey 't'
                        |> TuiTest.ensureViewHas "Quit"
                        |> TuiTest.ensureViewDoesNotHave "Next commit"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "Esc in search mode returns to browse, not close" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.pressKey '/'
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.pressKeyWith { key = Tui.Event.Escape, modifiers = [] }
                        -- Should still show help modal (back to browse mode)
                        |> TuiTest.ensureViewHas "Keybindings"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "j/k navigate in help modal browse mode" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        -- Navigating, should still show help modal
                        |> TuiTest.ensureViewHas "Keybindings"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "q quits even when help modal is open" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Keybindings"
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.expectExit
                        |> TuiTest.done
            , test "@ prefix in search mode filters by key name" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '?'
                        |> TuiTest.pressKey '/'
                        |> TuiTest.pressKey '@'
                        |> TuiTest.pressKey 't'
                        |> TuiTest.pressKey 'a'
                        |> TuiTest.pressKey 'b'
                        |> TuiTest.ensureViewHas "Switch pane"
                        |> TuiTest.ensureViewDoesNotHave "Quit"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "diff scroll reset"
            [ test "selecting a new commit resets diff scroll to top" <|
                \() ->
                    miniGitTest
                        -- Tab to focus the diff pane and scroll down
                        |> TuiTest.pressKeyWith { key = Tui.Event.Tab, modifiers = [] }
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        -- Scrolled down — top lines should be gone
                        |> TuiTest.ensureViewDoesNotHave "commit abc1234"
                        -- Tab back to commits, navigate to a new commit
                        |> TuiTest.pressKeyWith { key = Tui.Event.Tab, modifiers = [] }
                        |> TuiTest.pressKey 'j'
                        -- Should see the TOP of the new commit's diff
                        |> TuiTest.ensureViewHas "commit def5678"
                        |> TuiTest.ensureViewHas "Message for def5678"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "clicking a commit resets diff scroll to top" <|
                \() ->
                    miniGitTest
                        -- Tab to diff pane and scroll down
                        |> TuiTest.pressKeyWith { key = Tui.Event.Tab, modifiers = [] }
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewDoesNotHave "commit abc1234"
                        -- Click on a different commit
                        |> TuiTest.clickText "def5678"
                        -- Should see the TOP of the new diff
                        |> TuiTest.ensureViewHas "commit def5678"
                        |> TuiTest.ensureViewHas "Message for def5678"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "keybinding dispatch"
            [ test "j navigates via keybinding dispatch" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "down arrow navigates as alternate key" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKeyWith { key = Tui.Event.Arrow Tui.Event.Down, modifiers = [] }
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "filter (lazygit-style)"
            [ test "/ activates filter, shows Filter: in bottom bar" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '/'
                        |> TuiTest.ensureViewHas "Filter:"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "typing filters commits in real-time" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '/'
                        |> TuiTest.pressKey 'f'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKey 'x'
                        -- Only commits containing "fix" should be visible
                        |> TuiTest.ensureViewHas "Fix bug"
                        -- "Initial commit" should be filtered out
                        |> TuiTest.ensureViewDoesNotHave "Initial commit"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "Enter applies filter, shows matches status" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '/'
                        |> TuiTest.pressKey 'f'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.pressKeyWith { key = Tui.Event.Enter, modifiers = [] }
                        -- Filter stays active
                        |> TuiTest.ensureViewHas "Fix bug"
                        |> TuiTest.ensureViewDoesNotHave "Initial commit"
                        -- Status bar shows applied text
                        |> TuiTest.ensureViewHas "matches for 'fix'"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "Escape after Enter clears filter, shows all commits" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '/'
                        |> TuiTest.pressKey 'f'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.pressKeyWith { key = Tui.Event.Enter, modifiers = [] }
                        |> TuiTest.pressKeyWith { key = Tui.Event.Escape, modifiers = [] }
                        -- All commits should be visible again
                        |> TuiTest.ensureViewHas "Initial commit"
                        |> TuiTest.ensureViewHas "Fix bug"
                        -- Filter status should be gone
                        |> TuiTest.ensureViewDoesNotHave "Filter:"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "Escape while typing clears filter" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '/'
                        |> TuiTest.pressKey 'x'
                        |> TuiTest.pressKey 'y'
                        |> TuiTest.pressKey 'z'
                        |> TuiTest.pressKeyWith { key = Tui.Event.Escape, modifiers = [] }
                        -- All commits visible
                        |> TuiTest.ensureViewHas "Initial commit"
                        |> TuiTest.ensureViewDoesNotHave "Filter:"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "j/k navigate filtered list after Enter" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey '/'
                        |> TuiTest.pressKey 'a'
                        |> TuiTest.pressKey 'd'
                        |> TuiTest.pressKey 'd'
                        |> TuiTest.pressKeyWith { key = Tui.Event.Enter, modifiers = [] }
                        -- Now navigate within filtered results
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.expectRunning
                        |> TuiTest.done
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



-- Named TUI tests for elm-pages test


tuiTests : TuiTest.Test
tuiTests =
    TuiTest.describe "MiniGit"
        [ TuiTest.test "keyboard and click flow"
            (miniGitTest
                |> TuiTest.withModelToString Debug.toString
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'j'
                |> TuiTest.pressKey 'k'
                |> TuiTest.click { row = 2, col = 5 }
                |> TuiTest.expectRunning
            )
        ]



-- Inline MiniGit using Layout


type alias Commit =
    { sha : String
    , message : String
    }


type alias Model =
    { layout : Layout.State
    , commits : List Commit
    , diffContent : String
    , modal : Maybe ModalState
    , lastAction : String
    }


type ModalState
    = CommitModal { input : Input.State }
    | HelpModal HelpState


type alias HelpState =
    { mode : HelpMode
    , filter : Input.State
    , selectedIndex : Int
    }


type HelpMode
    = HelpBrowse
    | HelpSearch


type Action
    = DoNavigate Int
    | DoScrollDiff Int
    | DoQuit
    | DoSwitchPane
    | DoOpenCommit
    | DoOpenHelp


type Msg
    = KeyPressed Tui.Event.KeyEvent
    | Mouse Tui.Event.MouseEvent
    | GotPaste String
    | SelectCommit Int


testGlobalBindings : Keybinding.Group Action
testGlobalBindings =
    Keybinding.group "Global"
        [ Keybinding.binding (Tui.Event.Character 'q') "Quit" DoQuit
        , Keybinding.binding Tui.Event.Tab "Switch pane" DoSwitchPane
        , Keybinding.binding (Tui.Event.Character 'c') "Commit" DoOpenCommit
        , Keybinding.binding (Tui.Event.Character '?') "Help" DoOpenHelp
        ]


testCommitBindings : Keybinding.Group Action
testCommitBindings =
    Keybinding.group "Commits"
        [ Keybinding.binding (Tui.Event.Character 'j') "Next commit" (DoNavigate 1)
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)
        , Keybinding.binding (Tui.Event.Character 'k') "Previous commit" (DoNavigate -1)
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Up)
        ]


testDiffBindings : Keybinding.Group Action
testDiffBindings =
    Keybinding.group "Diff"
        [ Keybinding.binding (Tui.Event.Character 'j') "Scroll down" (DoScrollDiff 3)
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)
        , Keybinding.binding (Tui.Event.Character 'k') "Scroll up" (DoScrollDiff -3)
            |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Up)
        ]


testActiveBindings : Model -> List (Keybinding.Group Action)
testActiveBindings model =
    case Layout.focusedPane model.layout of
        Just "diff" ->
            [ testDiffBindings, testGlobalBindings ]

        _ ->
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
      , diffContent = diffForCommit "abc1234"
      , modal = Nothing
      , lastAction = ""
      }
    , Effect.none
    )


diffForCommit : String -> String
diffForCommit sha =
    "commit "
        ++ sha
        ++ "\nAuthor: Test\nDate: today\n\n    Message for "
        ++ sha
        ++ "\n---\n"
        ++ (List.range 1 40
                |> List.map (\i -> "+ line " ++ String.fromInt i ++ " of diff for " ++ sha)
                |> String.join "\n"
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
                        Tui.Screen.styled
                            { plain | fg = Just Ansi.Color.yellow, attributes = [ Tui.Screen.Bold ] }
                            ("▸ " ++ commit.sha ++ " " ++ commit.message)
                , default =
                    \commit ->
                        Tui.Screen.text ("  " ++ commit.sha ++ " " ++ commit.message)
                }
                model.commits
                |> Layout.withFilterable
                    (\commit -> commit.sha ++ " " ++ commit.message)
                    model.commits
            )
        , Layout.pane "diff"
            { title = "Diff", width = Layout.fillPortion 2 }
            (Layout.content
                (model.diffContent
                    |> String.lines
                    |> List.map Tui.Screen.text
                )
            )
        ]


miniGitUpdate : Msg -> Model -> ( Model, Effect Msg )
miniGitUpdate msg model =
    case model.modal of
        Just (CommitModal modalState) ->
            case msg of
                KeyPressed event ->
                    case event.key of
                        Tui.Event.Escape ->
                            ( { model | modal = Nothing }, Effect.none )

                        Tui.Event.Enter ->
                            let
                                commitMsg : String
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
                    case helpState.mode of
                        HelpBrowse ->
                            case event.key of
                                Tui.Event.Escape ->
                                    ( { model | modal = Nothing }, Effect.none )

                                Tui.Event.Character '/' ->
                                    ( { model | modal = Just (HelpModal { helpState | mode = HelpSearch }) }, Effect.none )

                                Tui.Event.Character 'j' ->
                                    ( { model | modal = Just (HelpModal { helpState | selectedIndex = helpState.selectedIndex + 1 }) }, Effect.none )

                                Tui.Event.Arrow Tui.Event.Down ->
                                    ( { model | modal = Just (HelpModal { helpState | selectedIndex = helpState.selectedIndex + 1 }) }, Effect.none )

                                Tui.Event.Character 'k' ->
                                    ( { model | modal = Just (HelpModal { helpState | selectedIndex = max 0 (helpState.selectedIndex - 1) }) }, Effect.none )

                                Tui.Event.Arrow Tui.Event.Up ->
                                    ( { model | modal = Just (HelpModal { helpState | selectedIndex = max 0 (helpState.selectedIndex - 1) }) }, Effect.none )

                                _ ->
                                    -- Fall through to global bindings
                                    case Keybinding.dispatch [ testGlobalBindings ] event of
                                        Just action ->
                                            handleAction action { model | modal = Nothing }

                                        Nothing ->
                                            ( model, Effect.none )

                        HelpSearch ->
                            case event.key of
                                Tui.Event.Escape ->
                                    ( { model | modal = Just (HelpModal { helpState | mode = HelpBrowse }) }, Effect.none )

                                Tui.Event.Enter ->
                                    ( { model | modal = Just (HelpModal { helpState | mode = HelpBrowse, selectedIndex = 0 }) }, Effect.none )

                                _ ->
                                    ( { model | modal = Just (HelpModal { helpState | filter = Input.update event helpState.filter, selectedIndex = 0 }) }, Effect.none )

                GotPaste pastedText ->
                    case helpState.mode of
                        HelpSearch ->
                            ( { model | modal = Just (HelpModal { helpState | filter = Input.insertText pastedText helpState.filter, selectedIndex = 0 }) }, Effect.none )

                        HelpBrowse ->
                            ( model, Effect.none )

                _ ->
                    ( model, Effect.none )

        Nothing ->
            case msg of
                KeyPressed event ->
                    -- Layout handles filter keys (/, typing, Enter, Escape) and
                    -- number keys for pane focus. Check it first.
                    case Layout.handleKeyEvent event (miniGitLayout model) model.layout of
                        ( newLayout, Just layoutMsg, _ ) ->
                            miniGitUpdate layoutMsg { model | layout = newLayout }

                        ( newLayout, Nothing, True ) ->
                            ( { model | layout = newLayout }, Effect.none )

                        ( _, Nothing, False ) ->
                            case Keybinding.dispatch (testActiveBindings model) event of
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

                SelectCommit index ->
                    let
                        sha : String
                        sha =
                            model.commits
                                |> List.drop index
                                |> List.head
                                |> Maybe.map .sha
                                |> Maybe.withDefault ""
                    in
                    ( { model
                        | layout = Layout.resetScroll "diff" model.layout
                        , diffContent = diffForCommit sha
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )


handleAction : Action -> Model -> ( Model, Effect Msg )
handleAction action model =
    case action of
        DoNavigate direction ->
            let
                ( newLayout, maybeMsg ) =
                    (if direction > 0 then
                        Layout.navigateDown "commits" (miniGitLayout model)

                     else
                        Layout.navigateUp "commits" (miniGitLayout model)
                    )
                        model.layout
            in
            -- navigateDown/Up fires SelectCommit when selection changes
            case maybeMsg of
                Just userMsg ->
                    miniGitUpdate userMsg { model | layout = newLayout }

                Nothing ->
                    ( { model | layout = newLayout }, Effect.none )

        DoQuit ->
            ( model, Effect.exit )

        DoSwitchPane ->
            let
                nextFocus : String
                nextFocus =
                    if Layout.focusedPane model.layout == Just "commits" then
                        "diff"

                    else
                        "commits"
            in
            ( { model | layout = Layout.focusPane nextFocus model.layout }, Effect.none )

        DoScrollDiff delta ->
            let
                newLayout : Layout.State
                newLayout =
                    if delta > 0 then
                        Layout.scrollDown "diff" delta model.layout

                    else
                        Layout.scrollUp "diff" (abs delta) model.layout
            in
            ( { model | layout = newLayout }, Effect.none )

        DoOpenCommit ->
            ( { model | modal = Just (CommitModal { input = Input.init "" }) }, Effect.none )

        DoOpenHelp ->
            ( { model
                | modal =
                    Just
                        (HelpModal
                            { mode = HelpBrowse
                            , filter = Input.init ""
                            , selectedIndex = 0
                            }
                        )
              }
            , Effect.none
            )


miniGitView : Tui.Context -> Model -> Tui.Screen.Screen
miniGitView ctx model =
    let
        layoutState : Layout.State
        layoutState =
            Layout.withContext { width = ctx.width, height = ctx.height } model.layout

        bgRows : List Tui.Screen.Screen
        bgRows =
            Layout.toRows layoutState (miniGitLayout model)

        bottomBar : Tui.Screen.Screen
        bottomBar =
            case Layout.filterStatusBar "commits" model.layout of
                Just filterBar ->
                    filterBar

                Nothing ->
                    if String.isEmpty model.lastAction then
                        Tui.Screen.empty

                    else
                        Tui.Screen.text (" " ++ model.lastAction)
    in
    (case model.modal of
        Just (CommitModal modalState) ->
            Tui.Modal.overlay
                { title = "Commit"
                , body =
                    [ Tui.Screen.text ""
                    , Input.view { width = 40 } modalState.input
                    , Tui.Screen.text ""
                    ]
                , footer = "Enter: confirm │ Esc: cancel"
                , width = 50
                }
                { width = ctx.width, height = ctx.height }
                bgRows

        Just (HelpModal helpState) ->
            let
                filterText : String
                filterText =
                    Input.text helpState.filter

                groups : List (Keybinding.Group Action)
                groups =
                    testActiveBindings model

                rowCount : Int
                rowCount =
                    Keybinding.helpRowCount filterText groups

                clampedIdx : Int
                clampedIdx =
                    clamp 0 (max 0 (rowCount - 1)) helpState.selectedIndex

                helpBody : List Tui.Screen.Screen
                helpBody =
                    Keybinding.helpRowsWithSelection clampedIdx filterText groups

                searchRow : List Tui.Screen.Screen
                searchRow =
                    case helpState.mode of
                        HelpSearch ->
                            [ Tui.Screen.concat
                                [ Tui.Screen.styled { plain | attributes = [ Tui.Screen.Dim ] } "/"
                                , Input.view { width = 40 } helpState.filter
                                ]
                            , Tui.Screen.text ""
                            ]

                        HelpBrowse ->
                            if not (String.isEmpty filterText) then
                                [ Tui.Screen.styled { plain | attributes = [ Tui.Screen.Dim ] } ("/" ++ filterText)
                                , Tui.Screen.text ""
                                ]

                            else
                                []

                footer : String
                footer =
                    case helpState.mode of
                        HelpSearch ->
                            "Enter: confirm │ Esc: cancel"

                        HelpBrowse ->
                            "j/k: navigate │ /: search │ Esc: close"
            in
            Tui.Modal.overlay
                { title = "Keybindings"
                , body = searchRow ++ helpBody
                , footer = footer
                , width = 50
                }
                { width = ctx.width, height = ctx.height }
                bgRows

        Nothing ->
            bgRows
    )
        |> (\rows -> Tui.Screen.lines (List.take (List.length rows - 1) rows ++ [ bottomBar ]))


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
