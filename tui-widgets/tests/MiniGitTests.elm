module MiniGitTests exposing (suite, tuiTests)

import Expect exposing (Expectation)
import MiniGit exposing (initialModelWithContext, miniGitLayout, miniGitTest)
import Test exposing (Test, describe, test)
import Test.Runner
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }
                        |> TuiTest.ensureViewDoesNotHave "Enter: confirm"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "enter confirms commit with typed message" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'c'
                        |> TuiTest.pressKey 'h'
                        |> TuiTest.pressKey 'i'
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        -- Scrolled down — top lines should be gone
                        |> TuiTest.ensureViewDoesNotHave "commit abc1234"
                        -- Tab back to commits, navigate to a new commit
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Tab, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Arrow Tui.Sub.Down, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Escape, modifiers = [] }
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
                        |> TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
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
