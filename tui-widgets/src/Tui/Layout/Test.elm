module Tui.Layout.Test exposing
    ( ensureFocusedPane
    , ensureSelectedIndex
    , ensureScrollPosition
    , ensurePaneHas, ensurePaneDoesNotHave
    , ensureUserModel
    )

{-| Test helpers for apps built with [`Layout.compileApp`](Tui-Layout#compileApp).

These build on [`TuiTest.ensureModel`](Tui-Test#ensureModel) to query
the opaque `FrameworkModel` for focus, selection, and scroll state — no
need to render debug info in your view or parse the screen output.

    import Tui.Layout.Test as LayoutTest

    test "Tab moves focus to diff pane" <|
        \() ->
            myApp
                |> TuiTest.pressKeyWith { key = Tui.Tab, modifiers = [] }
                |> LayoutTest.ensureFocusedPane "diff"
                |> TuiTest.expectRunning

    test "j navigates to third commit" <|
        \() ->
            myApp
                |> TuiTest.pressKeyN 2 'j'
                |> LayoutTest.ensureSelectedIndex "commits" 2
                |> TuiTest.expectRunning


## Layout State

@docs ensureFocusedPane
@docs ensureSelectedIndex
@docs ensureScrollPosition


## Pane Content

@docs ensurePaneHas, ensurePaneDoesNotHave


## User Model

@docs ensureUserModel

-}

import Expect
import Tui
import Tui.Layout as Layout
import Tui.Test as TuiTest


{-| Assert which pane is currently focused.

    test |> LayoutTest.ensureFocusedPane "commits"

-}
ensureFocusedPane :
    String
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
ensureFocusedPane expectedPaneId =
    TuiTest.ensureModel
        (\frameworkModel ->
            let
                actual : Maybe String
                actual =
                    Layout.frameworkFocusedPane frameworkModel
            in
            if actual == Just expectedPaneId then
                Expect.pass

            else
                Expect.fail
                    ("ensureFocusedPane: expected focused pane to be \""
                        ++ expectedPaneId
                        ++ "\" but it was "
                        ++ (case actual of
                                Just id ->
                                    "\"" ++ id ++ "\""

                                Nothing ->
                                    "Nothing (no pane focused)"
                           )
                    )
        )
        >> TuiTest.annotateAssertion ("ensureFocusedPane \"" ++ expectedPaneId ++ "\" ✓")


{-| Assert the selected index for a pane.

    test |> LayoutTest.ensureSelectedIndex "commits" 3

-}
ensureSelectedIndex :
    String
    -> Int
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
ensureSelectedIndex paneId expectedIndex =
    TuiTest.ensureModel
        (\frameworkModel ->
            let
                actual : Int
                actual =
                    Layout.frameworkSelectedIndex paneId frameworkModel
            in
            if actual == expectedIndex then
                Expect.pass

            else
                Expect.fail
                    ("ensureSelectedIndex: expected pane \""
                        ++ paneId
                        ++ "\" to have selected index "
                        ++ String.fromInt expectedIndex
                        ++ " but it was "
                        ++ String.fromInt actual
                    )
        )
        >> TuiTest.annotateAssertion ("ensureSelectedIndex \"" ++ paneId ++ "\" " ++ String.fromInt expectedIndex ++ " ✓")


{-| Assert the scroll position for a pane.

    test |> LayoutTest.ensureScrollPosition "docs" 0

-}
ensureScrollPosition :
    String
    -> Int
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
ensureScrollPosition paneId expectedOffset =
    TuiTest.ensureModel
        (\frameworkModel ->
            let
                actual : Int
                actual =
                    Layout.frameworkScrollPosition paneId frameworkModel
            in
            if actual == expectedOffset then
                Expect.pass

            else
                Expect.fail
                    ("ensureScrollPosition: expected pane \""
                        ++ paneId
                        ++ "\" to have scroll position "
                        ++ String.fromInt expectedOffset
                        ++ " but it was "
                        ++ String.fromInt actual
                    )
        )
        >> TuiTest.annotateAssertion ("ensureScrollPosition \"" ++ paneId ++ "\" " ++ String.fromInt expectedOffset ++ " ✓")


{-| Assert that a pane's rendered content contains the given text. Only
searches within the pane's border — text in other panes won't match.

The first argument is the pane **title** as it appears on screen (e.g.
`"Commits"`, not the pane ID `"commits"`).

    test
        |> LayoutTest.ensurePaneHas "Commits" "abc123"
        |> LayoutTest.ensurePaneDoesNotHave "Diff" "abc123"

-}
ensurePaneHas :
    String
    -> String
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
ensurePaneHas paneTitle needle =
    TuiTest.ensureView
        (\screenText ->
            let
                paneText : String
                paneText =
                    extractPaneText paneTitle screenText
            in
            if String.isEmpty paneText then
                Expect.fail
                    ("ensurePaneHas: could not find pane titled \""
                        ++ paneTitle
                        ++ "\" on screen.\n\nThe screen was:\n\n"
                        ++ indentText screenText
                    )

            else if String.contains needle paneText then
                Expect.pass

            else
                Expect.fail
                    ("ensurePaneHas: expected pane \""
                        ++ paneTitle
                        ++ "\" to contain:\n\n    \""
                        ++ needle
                        ++ "\"\n\nbut the pane content was:\n\n"
                        ++ indentText paneText
                    )
        )
        >> TuiTest.annotateAssertion ("ensurePaneHas \"" ++ paneTitle ++ "\" \"" ++ needle ++ "\" ✓")


{-| Assert that a pane's rendered content does NOT contain the given text.
The first argument is the pane **title** as it appears on screen.

    test |> LayoutTest.ensurePaneDoesNotHave "Diff" "Loading"

-}
ensurePaneDoesNotHave :
    String
    -> String
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
ensurePaneDoesNotHave paneTitle needle =
    TuiTest.ensureView
        (\screenText ->
            let
                paneText : String
                paneText =
                    extractPaneText paneTitle screenText
            in
            if String.isEmpty paneText then
                Expect.fail
                    ("ensurePaneDoesNotHave: could not find pane titled \""
                        ++ paneTitle
                        ++ "\" on screen.\n\nThe screen was:\n\n"
                        ++ indentText screenText
                    )

            else if String.contains needle paneText then
                Expect.fail
                    ("ensurePaneDoesNotHave: expected pane \""
                        ++ paneTitle
                        ++ "\" NOT to contain:\n\n    \""
                        ++ needle
                        ++ "\"\n\nbut the pane content was:\n\n"
                        ++ indentText paneText
                    )

            else
                Expect.pass
        )
        >> TuiTest.annotateAssertion ("ensurePaneDoesNotHave \"" ++ paneTitle ++ "\" \"" ++ needle ++ "\" ✓")


{-| Assert on the user model inside a `FrameworkModel`. Use this when you
need to check domain-specific state that isn't part of the layout framework.

    test
        |> LayoutTest.ensureUserModel
            (\model -> Expect.equal "abc123" model.selectedCommit)

-}
ensureUserModel :
    (model -> Expect.Expectation)
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
    -> TuiTest.TuiTest (Layout.FrameworkModel model msg) (Layout.FrameworkMsg msg)
ensureUserModel assertion =
    TuiTest.ensureModel
        (\frameworkModel ->
            assertion (Layout.frameworkUserModel frameworkModel)
        )



-- INTERNAL: Pane text extraction


{-| Extract the text content of a specific pane from the full screen text.
Finds the pane by its title in the top border, then extracts all text
between the left and right borders for that pane's column range.

Layout renders titles like `╭─[1]Commits───╮`. We search for the title
text followed by `─` (the border fill character) to find the pane.
-}
extractPaneText : String -> String -> String
extractPaneText paneTitle screenText =
    let
        screenLines : List String
        screenLines =
            String.lines screenText
    in
    case findPaneColumns paneTitle screenLines of
        Just ( startCol, endCol ) ->
            screenLines
                -- Skip the first line (border) and collect content lines
                |> List.filterMap (extractColumnsFromLine startCol endCol)
                |> String.join "\n"

        Nothing ->
            ""


{-| Find the column range (start, end) for a pane by its title.
Searches all lines for the title text followed by a border dash.
Returns the inner content columns (excluding border characters).
-}
findPaneColumns : String -> List String -> Maybe ( Int, Int )
findPaneColumns paneTitle lines =
    -- Layout renders: ╭─[1]Title────╮
    -- We search for "Title─" (title followed by border dash)
    let
        titleWithDash : String
        titleWithDash =
            paneTitle ++ "─"
    in
    findPaneColumnsHelp titleWithDash lines


findPaneColumnsHelp : String -> List String -> Maybe ( Int, Int )
findPaneColumnsHelp titleMarker lines =
    case lines of
        [] ->
            Nothing

        line :: rest ->
            case findSubstringIndex titleMarker line of
                Just titleStart ->
                    let
                        leftBorder : Int
                        leftBorder =
                            findBorderLeft titleStart line

                        rightBorder : Int
                        rightBorder =
                            findBorderRight (titleStart + String.length titleMarker) line
                    in
                    Just ( leftBorder, rightBorder )

                Nothing ->
                    findPaneColumnsHelp titleMarker rest


findSubstringIndex : String -> String -> Maybe Int
findSubstringIndex needle haystack =
    findSubstringIndexHelp needle haystack 0


findSubstringIndexHelp : String -> String -> Int -> Maybe Int
findSubstringIndexHelp needle haystack offset =
    if offset > String.length haystack - String.length needle then
        Nothing

    else if String.startsWith needle (String.dropLeft offset haystack) then
        Just offset

    else
        findSubstringIndexHelp needle haystack (offset + 1)


findBorderLeft : Int -> String -> Int
findBorderLeft pos line =
    if pos <= 0 then
        0

    else
        let
            ch : String
            ch =
                String.slice (pos - 1) pos line
        in
        if ch == "╭" || ch == "├" || ch == "│" then
            pos

        else
            findBorderLeft (pos - 1) line


findBorderRight : Int -> String -> Int
findBorderRight pos line =
    if pos >= String.length line then
        String.length line

    else
        let
            ch : String
            ch =
                String.slice pos (pos + 1) line
        in
        if ch == "╮" || ch == "┤" || ch == "│" then
            pos

        else
            findBorderRight (pos + 1) line


{-| Extract the text between two column positions from a line,
stripping border characters.
-}
extractColumnsFromLine : Int -> Int -> String -> Maybe String
extractColumnsFromLine startCol endCol line =
    if String.length line < endCol then
        Nothing

    else
        let
            slice : String
            slice =
                line
                    |> String.dropLeft startCol
                    |> String.left (endCol - startCol)
                    |> stripBorderChars
        in
        if String.isEmpty (String.trim slice) then
            Nothing

        else
            Just (String.trim slice)


stripBorderChars : String -> String
stripBorderChars s =
    s
        |> String.replace "│" ""
        |> String.replace "╭" ""
        |> String.replace "╮" ""
        |> String.replace "╰" ""
        |> String.replace "╯" ""
        |> String.replace "├" ""
        |> String.replace "┤" ""


indentText : String -> String
indentText text =
    text
        |> String.lines
        |> List.map (\line -> "    " ++ line)
        |> String.join "\n"
