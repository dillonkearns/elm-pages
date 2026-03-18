module Tui.Layout exposing
    ( Layout, Pane, horizontal, pane
    , PaneContent, content, selectableList
    , Width, fill, fillPortion, px
    , State, init, withContext
    , navigateDown, navigateUp, selectedIndex, setSelectedIndex, scrollPosition, resetScroll, scrollDown, scrollUp, contextOf
    , focusPane, focusedPane
    , withPrefix, withFooter, withTitleScreen
    , handleMouse
    , toScreen, toRows
    , navigationHelpRows
    )

{-| Split-pane layout with opaque state, selectable lists, and mouse dispatch.

Inspired by gocui/Ratatui. The framework tracks scroll offsets, selection
indices, and terminal dimensions in an opaque `State`. The user stores one
`State` field in their Model.

    import Tui.Layout as Layout

    type alias Model =
        { layout : Layout.State
        , commits : List Commit
        }

    view ctx model =
        Layout.horizontal
            [ Layout.pane "commits"
                { title = "Commits", width = Layout.fill }
                (Layout.selectableList
                    { onSelect = SelectCommit
                    , selected = \c -> Tui.text ("▸ " ++ c.sha)
                    , default = \c -> Tui.text ("  " ++ c.sha)
                    }
                    model.commits
                )
            ]
            |> Layout.toScreen (Layout.withContext ctx model.layout)

@docs Layout, Pane, horizontal, pane

@docs PaneContent, content, selectableList

@docs Width, fill, fillPortion, px

@docs State, init, withContext

@docs navigateDown, navigateUp, selectedIndex, setSelectedIndex, scrollPosition, resetScroll, scrollDown, scrollUp, contextOf

@docs focusPane, focusedPane

@docs withPrefix, withFooter, withTitleScreen

@docs handleMouse

@docs toScreen, toRows

@docs navigationHelpRows

-}

import Ansi.Color
import Array
import Dict exposing (Dict)
import Tui exposing (MouseEvent, Screen)
import Tui.Keybinding


{-| A layout of panes.
-}
type Layout msg
    = Horizontal (List (PaneConfig msg))


type alias PaneConfig msg =
    { id : String
    , title : String
    , width : Width
    , paneContent : PaneContent msg
    , prefix : Maybe String
    , footer : Maybe String
    , titleScreen : Maybe Screen
    }


{-| A pane in a layout (opaque).
-}
type Pane msg
    = PaneConstructor (PaneConfig msg)


{-| Content for a pane — either a static list of screens or a selectable list.

SelectableContent stores items lazily: the render functions are only applied
when `getContentLine` needs a specific visible item. This means a list of
10,000 items only renders the ~30 that are on screen (viewport-only rendering,
inspired by lazygit's `renderOnlyVisibleLines` and Ratatui's `ListState`).
-}
type PaneContent msg
    = StaticContent (List Screen)
    | SelectableContent
        { itemCount : Int
        , renderItem : Int -> Screen -- renders default view for item at index
        , renderSelected : Int -> Screen -- renders selected view for item at index
        , onSelect : Int -> msg
        }


{-| Width specification using integer weights (like elm-ui).
-}
type Width
    = Fill Int
    | Px Int


{-| Opaque state tracking scroll offsets, selection indices, and terminal
dimensions for all panes. Store ONE of these in your Model.
-}
type State
    = State
        { paneStates : Dict String PaneState
        , context : { width : Int, height : Int }
        , focusedPaneId : Maybe String
        }


type alias PaneState =
    { scrollOffset : Int
    , selectedIndex : Int
    }



-- CONSTRUCTORS


{-| Create a horizontal split layout.
-}
horizontal : List (Pane msg) -> Layout msg
horizontal panes =
    Horizontal (List.map (\(PaneConstructor config) -> config) panes)


{-| Create a pane.

    Layout.pane "commits"
        { title = "Commits", width = Layout.fill }
        (Layout.selectableList { ... } items)

-}
pane : String -> { title : String, width : Width } -> PaneContent msg -> Pane msg
pane id config paneContent =
    PaneConstructor
        { id = id
        , title = config.title
        , width = config.width
        , paneContent = paneContent
        , prefix = Nothing
        , footer = Nothing
        , titleScreen = Nothing
        }


{-| Static content — a list of screens, one per line. No selection behavior.
-}
content : List Screen -> PaneContent msg
content =
    StaticContent


{-| A selectable list. The framework tracks which item is selected and renders
the appropriate variant. Handles click-to-select and keyboard navigation.

    Layout.selectableList
        { onSelect = SelectCommit
        , selected = \commit -> Tui.styled selectedStyle commit.sha
        , default = \commit -> Tui.text commit.sha
        }
        model.commits

-}
selectableList :
    { onSelect : Int -> msg
    , selected : item -> Screen
    , default : item -> Screen
    }
    -> List item
    -> PaneContent msg
selectableList config items =
    let
        itemArray : Array.Array item
        itemArray =
            Array.fromList items
    in
    SelectableContent
        { itemCount = Array.length itemArray
        , renderItem =
            \i ->
                Array.get i itemArray
                    |> Maybe.map config.default
                    |> Maybe.withDefault Tui.empty
        , renderSelected =
            \i ->
                Array.get i itemArray
                    |> Maybe.map config.selected
                    |> Maybe.withDefault Tui.empty
        , onSelect = config.onSelect
        }



-- WIDTH


{-| Fill remaining space with weight 1.
-}
fill : Width
fill =
    Fill 1


{-| Fill remaining space with a weight. Two panes with `fillPortion 2` and
`fillPortion 1` split space 2:1, matching elm-ui's `fillPortion`.
-}
fillPortion : Int -> Width
fillPortion =
    Fill


{-| Fixed column width.
-}
px : Int -> Width
px =
    Px



-- STATE


{-| Initial empty state.
-}
init : State
init =
    State
        { paneStates = Dict.empty
        , context = { width = 80, height = 24 }
        , focusedPaneId = Nothing
        }


{-| Update the terminal dimensions in the state. Call this with the `Context`
from your `view` function.
-}
withContext : { a | width : Int, height : Int } -> State -> State
withContext ctx (State s) =
    State { s | context = { width = ctx.width, height = ctx.height } }


{-| Move selection down in a pane. Returns the updated state and the new
selected index. Clamps at item bounds and auto-scrolls to keep the
selection visible with padding (lazygit-style: 2 items visible below
when scrolling down, snap back into view after mouse scroll).

    ( newLayout, newIndex ) =
        Layout.navigateDown "commits" (myLayout model) model.layout

-}
navigateDown : String -> Layout msg -> State -> ( State, Int )
navigateDown paneId layout (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState

        itemCount : Int
        itemCount =
            getItemCountForPane paneId layout

        visibleHeight : Int
        visibleHeight =
            s.context.height - 2

        -- Clamp to valid range
        newIndex : Int
        newIndex =
            min (max 0 (itemCount - 1)) (ps.selectedIndex + 1)

        -- Auto-scroll: keep selection in view with padding
        scrollPadding : Int
        scrollPadding =
            2

        newOffset : Int
        newOffset =
            ensureVisible newIndex ps.scrollOffset visibleHeight itemCount scrollPadding
    in
    ( State
        { s
            | paneStates =
                Dict.insert paneId
                    { selectedIndex = newIndex, scrollOffset = newOffset }
                    s.paneStates
        }
    , newIndex
    )


{-| Move selection up in a pane. Returns the updated state and the new
selected index. Clamps at 0 and auto-scrolls to keep the selection
visible with padding.

    ( newLayout, newIndex ) =
        Layout.navigateUp "commits" (myLayout model) model.layout

-}
navigateUp : String -> Layout msg -> State -> ( State, Int )
navigateUp paneId layout (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState

        itemCount : Int
        itemCount =
            getItemCountForPane paneId layout

        visibleHeight : Int
        visibleHeight =
            s.context.height - 2

        newIndex : Int
        newIndex =
            max 0 (ps.selectedIndex - 1)

        scrollPadding : Int
        scrollPadding =
            2

        newOffset : Int
        newOffset =
            ensureVisible newIndex ps.scrollOffset visibleHeight itemCount scrollPadding
    in
    ( State
        { s
            | paneStates =
                Dict.insert paneId
                    { selectedIndex = newIndex, scrollOffset = newOffset }
                    s.paneStates
        }
    , newIndex
    )


{-| Adjust scroll offset to keep an index visible within the viewport,
with scroll padding on each side (lazygit-style).
-}
ensureVisible : Int -> Int -> Int -> Int -> Int -> Int
ensureVisible index scrollOffset visibleHeight itemCount padding =
    let
        maxOffset : Int
        maxOffset =
            max 0 (itemCount - visibleHeight)
    in
    if index < scrollOffset + padding then
        -- Selection too close to top (or above viewport): scroll up
        clamp 0 maxOffset (index - padding)

    else if index > scrollOffset + visibleHeight - 1 - padding then
        -- Selection too close to bottom (or below viewport): scroll down
        clamp 0 maxOffset (index - visibleHeight + 1 + padding)

    else
        -- Selection is in the comfortable zone: don't scroll
        scrollOffset


{-| Get item count for a specific pane from a Layout.
-}
getItemCountForPane : String -> Layout msg -> Int
getItemCountForPane paneId layout =
    case layout of
        Horizontal panes ->
            panes
                |> List.filter (\p -> p.id == paneId)
                |> List.head
                |> Maybe.map (\p -> contentLineCount p.paneContent)
                |> Maybe.withDefault 0


{-| Get the currently selected index for a pane.
-}
selectedIndex : String -> State -> Int
selectedIndex paneId (State s) =
    Dict.get paneId s.paneStates
        |> Maybe.map .selectedIndex
        |> Maybe.withDefault 0


{-| Set the selected index for a pane. Useful for restoring selection when
switching tabs, or programmatic navigation to a specific item.

    Layout.setSelectedIndex "modules" savedIndex model.layout

-}
setSelectedIndex : String -> Int -> State -> State
setSelectedIndex paneId index (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert paneId
                    { ps | selectedIndex = max 0 index }
                    s.paneStates
        }


{-| Get the current scroll position for a pane.
-}
scrollPosition : String -> State -> Int
scrollPosition paneId (State s) =
    Dict.get paneId s.paneStates
        |> Maybe.map .scrollOffset
        |> Maybe.withDefault 0


{-| Reset scroll position for a pane to 0. Call when loading new content
(e.g., reset the diff scroll when selecting a different commit).
-}
resetScroll : String -> State -> State
resetScroll paneId (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert paneId
                    { ps | scrollOffset = 0 }
                    s.paneStates
        }


{-| Scroll a pane down by the given number of lines.
-}
scrollDown : String -> Int -> State -> State
scrollDown paneId delta (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert paneId
                    { ps | scrollOffset = ps.scrollOffset + delta }
                    s.paneStates
        }


{-| Scroll a pane up by the given number of lines.
-}
scrollUp : String -> Int -> State -> State
scrollUp paneId delta (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert paneId
                    { ps | scrollOffset = max 0 (ps.scrollOffset - delta) }
                    s.paneStates
        }


{-| Set focus to a pane by ID. The focused pane gets green borders and
the active selection highlight style (like gocui's `SetCurrentView`).
-}
focusPane : String -> State -> State
focusPane paneId (State s) =
    State { s | focusedPaneId = Just paneId }


{-| Get the currently focused pane ID, if any.
-}
focusedPane : State -> Maybe String
focusedPane (State s) =
    s.focusedPaneId


{-| Add a prefix badge to the pane title (rendered before the title in the border).
Like gocui's `TitlePrefix` — used for keyboard shortcut indicators like `[4]`.

    Layout.pane "commits" { ... } content
        |> Layout.withPrefix "[4]"

-}
withPrefix : String -> Pane msg -> Pane msg
withPrefix prefixText (PaneConstructor config) =
    PaneConstructor { config | prefix = Just prefixText }


{-| Add a footer to the pane (rendered right-aligned on the bottom border).
Like gocui's `Footer` — used for item counts like `3 of 300`.

    Layout.pane "commits" { ... } content
        |> Layout.withFooter "3 of 300"

-}
withFooter : String -> Pane msg -> Pane msg
withFooter footerText (PaneConstructor config) =
    PaneConstructor { config | footer = Just footerText }


{-| Set a styled Screen as the pane title. Overrides the plain-text title
from the `pane` constructor. Useful for tab indicators or styled badges:

    Layout.pane "modules"
        { title = "Modules", width = Layout.fill }
        myContent
        |> Layout.withTitleScreen
            (Tui.concat
                [ Tui.text "[1]" |> Tui.bold |> Tui.fg Ansi.Color.cyan
                , Tui.text "Modules" |> Tui.bold
                , Tui.text " [2]" |> Tui.dim
                , Tui.text "Changes" |> Tui.dim
                ]
            )

-}
withTitleScreen : Screen -> Pane msg -> Pane msg
withTitleScreen screen (PaneConstructor config) =
    PaneConstructor { config | titleScreen = Just screen }


{-| Get the context stored in the state. Useful for passing to `handleMouse`
when `update` doesn't receive `Context` directly.
-}
contextOf : State -> { width : Int, height : Int }
contextOf (State s) =
    s.context


defaultPaneState : PaneState
defaultPaneState =
    { scrollOffset = 0, selectedIndex = 0 }


contentLineCount : PaneContent msg -> Int
contentLineCount paneContent =
    case paneContent of
        StaticContent lines ->
            List.length lines

        SelectableContent { itemCount } ->
            itemCount


clampScroll : Int -> Int -> Int -> Int
clampScroll contentLen visibleHeight offset =
    clamp 0 (max 0 (contentLen - visibleHeight)) offset


scrollbarBorder : Tui.Style -> PaneContent msg -> PaneState -> Int -> Int -> Screen
scrollbarBorder borderStyle paneContents ps contentRow totalHeight =
    let
        contentLen : Int
        contentLen =
            contentLineCount paneContents

        visibleHeight : Int
        visibleHeight =
            totalHeight - 2
    in
    if contentLen > visibleHeight then
        let
            thumbSize : Int
            thumbSize =
                max 1 (visibleHeight * visibleHeight // contentLen)

            thumbPos : Int
            thumbPos =
                ps.scrollOffset * (visibleHeight - thumbSize) // max 1 (contentLen - visibleHeight)
        in
        if contentRow >= thumbPos && contentRow < thumbPos + thumbSize then
            Tui.styled borderStyle "█"

        else
            Tui.styled borderStyle "│"

    else
        Tui.styled borderStyle "│"



-- MOUSE DISPATCH


{-| Handle a mouse event. Updates internal state (scroll, selection) and
returns the updated state plus an optional user message from click handlers.
Pass the terminal context for correct pane hit-testing.
-}
handleMouse : MouseEvent -> { width : Int, height : Int } -> Layout msg -> State -> ( State, Maybe msg )
handleMouse mouseEvent ctx (Horizontal panes) (State s) =
    let
        -- Persist context so contextOf returns correct values next time
        sWithCtx :
            { paneStates : Dict String PaneState
            , context : { width : Int, height : Int }
            , focusedPaneId : Maybe String
            }
        sWithCtx =
            { s | context = ctx }

        widths : List Int
        widths =
            resolveWidths ctx.width (List.map .width panes)

        panesWithBounds : List { config : PaneConfig msg, startCol : Int, endCol : Int }
        panesWithBounds =
            List.map2 Tuple.pair panes widths
                |> List.foldl
                    (\( paneConfig, w ) ( acc, col ) ->
                        ( acc ++ [ { config = paneConfig, startCol = col, endCol = col + w } ]
                        , col + w
                        )
                    )
                    ( [], 0 )
                |> Tuple.first
    in
    case mouseEvent of
        Tui.ScrollDown { col, amount } ->
            case findPaneAt col panesWithBounds of
                Just { config } ->
                    let
                        ps : PaneState
                        ps =
                            Dict.get config.id sWithCtx.paneStates
                                |> Maybe.withDefault defaultPaneState

                        delta : Int
                        delta =
                            amount * 3

                        newOffset : Int
                        newOffset =
                            clampScroll (contentLineCount config.paneContent) (ctx.height - 2) (ps.scrollOffset + delta)
                    in
                    -- gocui pattern: skip state update entirely when scroll is a no-op
                    -- at the boundary. This prevents unnecessary re-renders that cause
                    -- flicker with high-frequency trackpad momentum events.
                    if newOffset == ps.scrollOffset then
                        ( State { sWithCtx | focusedPaneId = Just config.id }, Nothing )

                    else
                        ( State
                            { sWithCtx
                                | paneStates =
                                    Dict.insert config.id
                                        { ps | scrollOffset = newOffset }
                                        sWithCtx.paneStates
                                , focusedPaneId = Just config.id
                            }
                        , Nothing
                        )

                Nothing ->
                    ( State sWithCtx, Nothing )

        Tui.ScrollUp { col, amount } ->
            case findPaneAt col panesWithBounds of
                Just { config } ->
                    let
                        ps : PaneState
                        ps =
                            Dict.get config.id sWithCtx.paneStates
                                |> Maybe.withDefault defaultPaneState

                        delta : Int
                        delta =
                            amount * 3

                        newOffset : Int
                        newOffset =
                            max 0 (ps.scrollOffset - delta)
                    in
                    -- gocui pattern: skip when at boundary (offset already 0)
                    if newOffset == ps.scrollOffset then
                        ( State sWithCtx, Nothing )

                    else
                        ( State
                            { sWithCtx
                                | paneStates =
                                    Dict.insert config.id
                                        { ps | scrollOffset = newOffset }
                                        sWithCtx.paneStates
                            }
                        , Nothing
                        )

                Nothing ->
                    ( State sWithCtx, Nothing )

        Tui.Click { row, col } ->
            case findPaneAt col panesWithBounds of
                Just { config } ->
                    case config.paneContent of
                        SelectableContent { onSelect } ->
                            let
                                contentRow : Int
                                contentRow =
                                    row - 1

                                ps : PaneState
                                ps =
                                    Dict.get config.id sWithCtx.paneStates
                                        |> Maybe.withDefault defaultPaneState

                                clickedIndex : Int
                                clickedIndex =
                                    contentRow + ps.scrollOffset
                            in
                            ( State
                                { sWithCtx
                                    | paneStates =
                                        Dict.insert config.id
                                            { ps | selectedIndex = clickedIndex }
                                            sWithCtx.paneStates
                                    , focusedPaneId = Just config.id
                                }
                            , Just (onSelect clickedIndex)
                            )

                        StaticContent _ ->
                            ( State { sWithCtx | focusedPaneId = Just config.id }, Nothing )

                Nothing ->
                    ( State sWithCtx, Nothing )


findPaneAt : Int -> List { config : PaneConfig msg, startCol : Int, endCol : Int } -> Maybe { config : PaneConfig msg, startCol : Int, endCol : Int }
findPaneAt col panesWithBounds =
    panesWithBounds
        |> List.filter (\{ startCol, endCol } -> col >= startCol && col < endCol)
        |> List.head



-- RENDERING


{-| Render the layout to a Screen using the given state.
-}
toScreen : State -> Layout msg -> Screen
toScreen state layout =
    Tui.lines (toRows state layout)


{-| Render the layout to a list of row Screens (one per terminal row).

This is useful for compositing modals or overlays on top of the layout —
you can replace specific rows with modal content, then wrap with `Tui.lines`.

-}
toRows : State -> Layout msg -> List Screen
toRows (State s) (Horizontal panes) =
    let
        totalWidth : Int
        totalWidth =
            s.context.width

        totalHeight : Int
        totalHeight =
            s.context.height

        widths : List Int
        widths =
            resolveWidths totalWidth (List.map .width panes)

        panesWithWidths : List ( PaneConfig msg, Int )
        panesWithWidths =
            List.map2 Tuple.pair panes widths

        paneCount : Int
        paneCount =
            List.length panes

        renderRow : Int -> Screen
        renderRow row =
            Tui.concat
                (panesWithWidths
                    |> List.indexedMap
                        (\paneIdx ( paneConfig, w ) ->
                            let
                                innerW : Int
                                innerW =
                                    if paneIdx == 0 then
                                        w - 2

                                    else
                                        w - 1

                                isFirstPane : Bool
                                isFirstPane =
                                    paneIdx == 0

                                isLastPane : Bool
                                isLastPane =
                                    paneIdx == paneCount - 1

                                isFocused : Bool
                                isFocused =
                                    s.focusedPaneId == Just paneConfig.id

                                borderStyle : Tui.Style
                                borderStyle =
                                    if isFocused then
                                        { fg = Just Ansi.Color.green, bg = Nothing, attributes = [ Tui.Bold ] }

                                    else
                                        { fg = Nothing, bg = Nothing, attributes = [ Tui.Dim ] }
                            in
                            if row == 0 then
                                let
                                    titleText : String
                                    titleText =
                                        (paneConfig.prefix |> Maybe.withDefault "") ++ paneConfig.title

                                    titleContent : Screen
                                    titleContent =
                                        case paneConfig.titleScreen of
                                            Just screen ->
                                                Tui.truncateWidth innerW screen

                                            Nothing ->
                                                Tui.styled borderStyle titleText

                                    titleWidth : Int
                                    titleWidth =
                                        case paneConfig.titleScreen of
                                            Just screen ->
                                                String.length (Tui.toString (Tui.truncateWidth innerW screen))

                                            Nothing ->
                                                String.length titleText

                                    fillLen : Int
                                    fillLen =
                                        max 0 (innerW - titleWidth)
                                in
                                Tui.concat
                                    [ Tui.styled borderStyle
                                        (if isFirstPane then
                                            "╭"

                                         else
                                            "┬"
                                        )
                                    , titleContent
                                    , Tui.styled borderStyle (String.repeat fillLen "─")
                                    , if isLastPane then
                                        Tui.styled borderStyle "╮"

                                      else
                                        Tui.empty
                                    ]

                            else if row == totalHeight - 1 then
                                let
                                    footerText : String
                                    footerText =
                                        paneConfig.footer |> Maybe.withDefault ""

                                    footerLen : Int
                                    footerLen =
                                        String.length footerText

                                    dashLen : Int
                                    dashLen =
                                        max 0 (innerW - footerLen)
                                in
                                Tui.concat
                                    [ Tui.styled borderStyle
                                        (if isFirstPane then
                                            "╰"

                                         else
                                            "┴"
                                        )
                                    , Tui.styled borderStyle (String.repeat dashLen "─")
                                    , if footerLen > 0 then
                                        Tui.styled borderStyle footerText

                                      else
                                        Tui.empty
                                    , if isLastPane then
                                        Tui.styled borderStyle "╯"

                                      else
                                        Tui.empty
                                    ]

                            else
                                let
                                    ps : PaneState
                                    ps =
                                        Dict.get paneConfig.id s.paneStates
                                            |> Maybe.withDefault defaultPaneState

                                    contentRow : Int
                                    contentRow =
                                        row - 1

                                    lineScreen : Screen
                                    lineScreen =
                                        getContentLine paneConfig ps contentRow

                                    lineText : String
                                    lineText =
                                        Tui.toString lineScreen

                                    lineWidth : Int
                                    lineWidth =
                                        String.length lineText

                                    truncatedLine : Screen
                                    truncatedLine =
                                        Tui.truncateWidth innerW lineScreen

                                    actualWidth : Int
                                    actualWidth =
                                        min lineWidth innerW

                                    padding : Int
                                    padding =
                                        max 0 (innerW - actualWidth)

                                    -- For selected rows in selectable lists, extend the
                                    -- selection highlight across the full pane width
                                    -- (lazygit fills the entire row with the highlight color)
                                    isSelectedRow : Bool
                                    isSelectedRow =
                                        case paneConfig.paneContent of
                                            SelectableContent _ ->
                                                (contentRow + ps.scrollOffset) == ps.selectedIndex

                                            StaticContent _ ->
                                                False

                                    paddingScreen : Screen
                                    paddingScreen =
                                        if isSelectedRow && padding > 0 then
                                            -- Extend the selection highlight across full pane width
                                            Tui.styled (Tui.extractStyle lineScreen) (String.repeat padding " ")

                                        else
                                            Tui.text (String.repeat padding " ")
                                in
                                Tui.concat
                                    [ Tui.styled borderStyle "│"
                                    , truncatedLine
                                    , paddingScreen
                                    , scrollbarBorder borderStyle paneConfig.paneContent ps contentRow totalHeight
                                    ]
                        )
                )
    in
    List.range 0 (totalHeight - 1)
        |> List.map renderRow


getContentLine : PaneConfig msg -> PaneState -> Int -> Screen
getContentLine paneConfig ps contentRow =
    let
        scrolledRow : Int
        scrolledRow =
            contentRow + ps.scrollOffset
    in
    case paneConfig.paneContent of
        StaticContent lines ->
            lines
                |> List.drop scrolledRow
                |> List.head
                |> Maybe.withDefault Tui.empty

        SelectableContent { renderItem, renderSelected } ->
            if scrolledRow == ps.selectedIndex then
                renderSelected scrolledRow

            else
                renderItem scrolledRow


resolveWidths : Int -> List Width -> List Int
resolveWidths totalWidth widthSpecs =
    let
        fixedTotal : Int
        fixedTotal =
            widthSpecs
                |> List.filterMap
                    (\w ->
                        case w of
                            Px n ->
                                Just n

                            Fill _ ->
                                Nothing
                    )
                |> List.sum

        totalWeight : Int
        totalWeight =
            widthSpecs
                |> List.filterMap
                    (\w ->
                        case w of
                            Fill weight ->
                                Just weight

                            Px _ ->
                                Nothing
                    )
                |> List.sum

        remaining : Int
        remaining =
            totalWidth - fixedTotal
    in
    widthSpecs
        |> List.map
            (\w ->
                case w of
                    Px n ->
                        n

                    Fill weight ->
                        if totalWeight > 0 then
                            (remaining * weight) // totalWeight

                        else
                            0
            )


{-| Auto-generated help rows for Layout's built-in mouse interactions.
Include these in your help screen so users know about scroll and click.

    helpBody =
        Keybinding.helpRows filterText myBindings
            ++ [ Tui.text "" ]
            ++ Layout.navigationHelpRows

-}
navigationHelpRows : List Screen
navigationHelpRows =
    [ Tui.Keybinding.sectionHeader "Navigation"
    , Tui.Keybinding.infoRow "scroll ↑" "Scroll up"
    , Tui.Keybinding.infoRow "scroll ↓" "Scroll down"
    , Tui.Keybinding.infoRow "click" "Select item"
    ]
