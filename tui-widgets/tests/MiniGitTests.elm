module MiniGitTests exposing (suite, tuiTests)

import Expect exposing (Expectation)
import MiniGit exposing (initialModelWithContext, miniGitLayout, miniGitTest)
import Test exposing (Test, describe, test)
import Test.Runner
import Test.Tui as TuiTest
import Tui.Layout as Layout
import Tui.Sub


suite : Test
suite =
    describe "MiniGit"
        [ describe "keyboard navigation"
            [ test "initial view shows commit list with first selected" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.ensureViewHas "▸ abc1234"
                        , TuiTest.ensureViewHas "def5678"
                        , TuiTest.expectRunning
                        ]
            , test "j moves selection down" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'j'
                        , TuiTest.ensureViewHas "▸ def5678"
                        , TuiTest.expectRunning
                        ]
            , test "k moves selection up" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'k'
                        , TuiTest.ensureViewHas "▸ abc1234"
                        , TuiTest.expectRunning
                        ]
            , test "q exits" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'q'
                        , TuiTest.expectExit
                        ]
            ]
        , describe "mouse interactions"
            [ test "clicking on a commit selects it (coordinates)" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.click { row = 2, col = 5 }
                        , TuiTest.ensureViewHas "▸ def5678"
                        , TuiTest.expectRunning
                        ]
            , test "clickText finds and clicks by content" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.clickText "345cdef"
                        , TuiTest.ensureViewHas "▸ 345cdef"
                        , TuiTest.expectRunning
                        ]
            , test "clickText on last item" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.clickText "bbb2222"
                        , TuiTest.ensureViewHas "▸ bbb2222"
                        , TuiTest.expectRunning
                        ]
            , test "clickText fails with helpful message when text not found" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.clickText "nonexistent"
                        , TuiTest.expectRunning
                        ]
                        |> expectFailureContaining "nonexistent"
            , test "scroll down moves viewport" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.scrollDown { row = 2, col = 5 }
                        , TuiTest.expectRunning
                        ]
            , test "clicking blank space in a resized diff pane still focuses that pane" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.ensureModel
                            (\model ->
                                Layout.focusedPane model.layout
                                    |> Expect.equal (Just "commits")
                            )
                        , TuiTest.resize { width = 120, height = 24 }
                        , TuiTest.click { row = 1, col = 100 }
                        , TuiTest.ensureModel
                            (\model ->
                                Layout.focusedPane model.layout
                                    |> Expect.equal (Just "diff")
                            )
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "Layout.resetScroll"
            [ test "resetScroll sets scroll to 0" <|
                \() ->
                    let
                        initialModel =
                            initialModelWithContext { width = 80, height = 24 }

                        ( state, _ ) =
                            Layout.navigateDown "commits"
                                (miniGitLayout initialModel)
                                initialModel.layout
                    in
                    Layout.scrollPosition "commits" (Layout.resetScroll "commits" state)
                        |> Expect.equal 0
            ]
        , describe "layout"
            [ test "shows pane titles" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.ensureViewHas "Commits"
                        , TuiTest.ensureViewHas "Diff"
                        , TuiTest.expectRunning
                        ]
            , test "shows box borders" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.ensureViewHas "╭"
                        , TuiTest.ensureViewHas "╮"
                        , TuiTest.ensureViewHas "│"
                        , TuiTest.ensureViewHas "─"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "commit dialog"
            [ test "c opens commit dialog" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.ensureViewHas "Commit"
                        , TuiTest.ensureViewHas "Enter: confirm"
                        , TuiTest.expectRunning
                        ]
            , test "typing in commit dialog" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.pressKey 'f'
                        , TuiTest.pressKey 'i'
                        , TuiTest.pressKey 'x'
                        , TuiTest.ensureViewHas "fix"
                        , TuiTest.expectRunning
                        ]
            , test "escape dismisses commit dialog" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.ensureViewHas "Commit"
                        , TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }
                        , TuiTest.ensureViewDoesNotHave "Enter: confirm"
                        , TuiTest.expectRunning
                        ]
            , test "enter confirms commit with typed message" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.pressKey 'h'
                        , TuiTest.pressKey 'i'
                        , TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
                        , TuiTest.ensureViewHas "Committed: hi"
                        , TuiTest.ensureViewDoesNotHave "Enter: confirm"
                        , TuiTest.expectRunning
                        ]
            , test "keys don't navigate while modal is open" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'

                        -- j should type into input, not navigate commits
                        , TuiTest.ensureViewHas "jjj"
                        , TuiTest.ensureViewHas "▸ abc1234"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "bracketed paste"
            [ test "paste inserts text into commit dialog" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.paste "fix: resolve null pointer in parser"
                        , TuiTest.ensureViewHas "fix: resolve null pointer"
                        , TuiTest.expectRunning
                        ]
            , test "paste after typing appends at cursor" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.pressKey 'A'
                        , TuiTest.pressKey 'B'
                        , TuiTest.paste "CD"
                        , TuiTest.pressKey 'E'
                        , TuiTest.ensureViewHas "ABCDE"
                        , TuiTest.expectRunning
                        ]
            , test "paste with enter confirms the pasted message" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.paste "docs: update README"
                        , TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
                        , TuiTest.ensureViewHas "Committed: docs: update README"
                        , TuiTest.expectRunning
                        ]
            , test "paste with newlines strips them for single-line input" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'c'
                        , TuiTest.paste "line one\nline two\nline three"
                        , TuiTest.ensureViewHas "line one line two line three"
                        , TuiTest.expectRunning
                        ]
            , test "paste is ignored when no modal is open" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.paste "should be ignored"
                        , TuiTest.ensureViewHas "▸ abc1234"
                        , TuiTest.ensureViewDoesNotHave "should be ignored"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "help modal"
            [ test "? opens help modal" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '?'
                        , TuiTest.ensureViewHas "Keybindings"
                        , TuiTest.ensureViewHas "Esc: close"
                        , TuiTest.expectRunning
                        ]
            , test "help shows binding descriptions" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '?'
                        , TuiTest.ensureViewHas "Quit"
                        , TuiTest.ensureViewHas "Next commit"
                        , TuiTest.expectRunning
                        ]
            , test "escape closes help" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '?'
                        , TuiTest.ensureViewHas "Keybindings"
                        , TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }
                        , TuiTest.ensureViewDoesNotHave "Keybindings"
                        , TuiTest.expectRunning
                        ]
            , test "/ enters search mode, typing filters by description" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '?'
                        , TuiTest.pressKey '/'
                        , TuiTest.pressKey 'q'
                        , TuiTest.pressKey 'u'
                        , TuiTest.pressKey 'i'
                        , TuiTest.pressKey 't'
                        , TuiTest.ensureViewHas "Quit"
                        , TuiTest.ensureViewDoesNotHave "Next commit"
                        , TuiTest.expectRunning
                        ]
            , test "Esc in search mode returns to browse, not close" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '?'
                        , TuiTest.pressKey '/'
                        , TuiTest.pressKey 'q'
                        , TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }

                        -- Should still show help modal (back to browse mode)
                        , TuiTest.ensureViewHas "Keybindings"
                        , TuiTest.expectRunning
                        ]
            , test "j/k navigate in help modal browse mode" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '?'
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'

                        -- Navigating, should still show help modal
                        , TuiTest.ensureViewHas "Keybindings"
                        , TuiTest.expectRunning
                        ]
            , test "q quits even when help modal is open" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '?'
                        , TuiTest.ensureViewHas "Keybindings"
                        , TuiTest.pressKey 'q'
                        , TuiTest.expectExit
                        ]
            , test "@ prefix in search mode filters by key name" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '?'
                        , TuiTest.pressKey '/'
                        , TuiTest.pressKey '@'
                        , TuiTest.pressKey 't'
                        , TuiTest.pressKey 'a'
                        , TuiTest.pressKey 'b'
                        , TuiTest.ensureViewHas "Switch pane"
                        , TuiTest.ensureViewDoesNotHave "Quit"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "diff scroll reset"
            [ test "selecting a new commit resets diff scroll to top" <|
                \() ->
                    TuiTest.expect miniGitTest
                        -- Tab to focus the diff pane and scroll down
                        [ TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'

                        -- Scrolled down — top lines should be gone
                        , TuiTest.ensureViewDoesNotHave "commit abc1234"

                        -- Tab back to commits, navigate to a new commit
                        , TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                        , TuiTest.pressKey 'j'

                        -- Should see the TOP of the new commit's diff
                        , TuiTest.ensureViewHas "commit def5678"
                        , TuiTest.ensureViewHas "Message for def5678"
                        , TuiTest.expectRunning
                        ]
            , test "clicking a commit resets diff scroll to top" <|
                \() ->
                    TuiTest.expect miniGitTest
                        -- Tab to diff pane and scroll down
                        [ TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'
                        , TuiTest.pressKey 'j'
                        , TuiTest.ensureViewDoesNotHave "commit abc1234"

                        -- Click on a different commit
                        , TuiTest.clickText "def5678"

                        -- Should see the TOP of the new diff
                        , TuiTest.ensureViewHas "commit def5678"
                        , TuiTest.ensureViewHas "Message for def5678"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "keybinding dispatch"
            [ test "j navigates via keybinding dispatch" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey 'j'
                        , TuiTest.ensureViewHas "▸ def5678"
                        , TuiTest.expectRunning
                        ]
            , test "down arrow navigates as alternate key" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKeyWith { key = Tui.Sub.Arrow Tui.Sub.Down, modifiers = [] }
                        , TuiTest.ensureViewHas "▸ def5678"
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "filter (lazygit-style)"
            [ test "/ activates filter, shows Filter: in bottom bar" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '/'
                        , TuiTest.ensureViewHas "Filter:"
                        , TuiTest.expectRunning
                        ]
            , test "typing filters commits in real-time" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '/'
                        , TuiTest.pressKey 'f'
                        , TuiTest.pressKey 'i'
                        , TuiTest.pressKey 'x'

                        -- Only commits containing "fix" should be visible
                        , TuiTest.ensureViewHas "Fix bug"

                        -- "Initial commit" should be filtered out
                        , TuiTest.ensureViewDoesNotHave "Initial commit"
                        , TuiTest.expectRunning
                        ]
            , test "Enter applies filter, shows matches status" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '/'
                        , TuiTest.pressKey 'f'
                        , TuiTest.pressKey 'i'
                        , TuiTest.pressKey 'x'
                        , TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }

                        -- Filter stays active
                        , TuiTest.ensureViewHas "Fix bug"
                        , TuiTest.ensureViewDoesNotHave "Initial commit"

                        -- Status bar shows applied text
                        , TuiTest.ensureViewHas "matches for 'fix'"
                        , TuiTest.expectRunning
                        ]
            , test "Escape after Enter clears filter, shows all commits" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '/'
                        , TuiTest.pressKey 'f'
                        , TuiTest.pressKey 'i'
                        , TuiTest.pressKey 'x'
                        , TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
                        , TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }

                        -- All commits should be visible again
                        , TuiTest.ensureViewHas "Initial commit"
                        , TuiTest.ensureViewHas "Fix bug"

                        -- Filter status should be gone
                        , TuiTest.ensureViewDoesNotHave "Filter:"
                        , TuiTest.expectRunning
                        ]
            , test "Escape while typing clears filter" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '/'
                        , TuiTest.pressKey 'x'
                        , TuiTest.pressKey 'y'
                        , TuiTest.pressKey 'z'
                        , TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }

                        -- All commits visible
                        , TuiTest.ensureViewHas "Initial commit"
                        , TuiTest.ensureViewDoesNotHave "Filter:"
                        , TuiTest.expectRunning
                        ]
            , test "j/k navigate filtered list after Enter" <|
                \() ->
                    TuiTest.expect miniGitTest
                        [ TuiTest.pressKey '/'
                        , TuiTest.pressKey 'a'
                        , TuiTest.pressKey 'd'
                        , TuiTest.pressKey 'd'
                        , TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }

                        -- Now navigate within filtered results
                        , TuiTest.pressKey 'j'
                        , TuiTest.expectRunning
                        ]
            ]
        , describe "snapshots"
            [ test "model state shows layout changes" <|
                \() ->
                    TuiTest.snapshots miniGitTest
                        [ TuiTest.withModelToString Debug.toString
                        , TuiTest.pressKey 'j'
                        ]
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
            miniGitTest
            [ TuiTest.withModelToString Debug.toString
            , TuiTest.pressKey 'j'
            , TuiTest.pressKey 'j'
            , TuiTest.pressKey 'j'
            , TuiTest.pressKey 'k'
            , TuiTest.click { row = 2, col = 5 }
            , TuiTest.expectRunning
            ]
        ]
