module Tui.Layout exposing
    ( Layout, Pane, horizontal, vertical, pane, paneGroup, TabConfig
    , PaneContent, content, selectableList
    , Width, fill, fillPortion, px
    , State, init, withContext
    , navigateDown, navigateUp, selectedIndex, setSelectedIndex, itemCount, scrollPosition, scrollInfo, resetScroll, scrollDown, scrollUp, contextOf
    , switchTab, activeTab
    , focusPane, focusedPane
    , toggleMaximize, isMaximized
    , withPrefix, withFooter, withTitleScreen, withFooterScreen, withInlineFooter
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

@docs Layout, Pane, horizontal, vertical, pane, paneGroup, TabConfig

@docs PaneContent, content, selectableList

@docs Width, fill, fillPortion, px

@docs State, init, withContext

@docs navigateDown, navigateUp, selectedIndex, setSelectedIndex, itemCount, scrollPosition, scrollInfo, resetScroll, scrollDown, scrollUp, contextOf

@docs switchTab, activeTab

@docs focusPane, focusedPane
@docs toggleMaximize, isMaximized

@docs withPrefix, withFooter, withTitleScreen, withFooterScreen, withInlineFooter

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
    | Vertical (List (PaneConfig msg))


type alias PaneConfig msg =
    { id : String
    , title : String
    , width : Width
    , paneContent : PaneContent msg
    , prefix : Maybe String
    , footer : Maybe String
    , titleScreen : Maybe Screen
    , footerScreen : Maybe Screen
    , inlineFooter : Maybe Screen
    , tabMapping : Maybe { activeTab : String, tabIds : List String }
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
        , maximizedPaneId : Maybe String
        , activeTabMap : Dict String String
        }


type alias PaneState =
    { scrollOffset : Int
    , selectedIndex : Int
    }



-- CONSTRUCTORS


{-| Create a horizontal split layout (panes side by side).
-}
horizontal : List (Pane msg) -> Layout msg
horizontal panes =
    Horizontal (List.map (\(PaneConstructor config) -> config) panes)


{-| Create a vertical split layout (panes stacked top to bottom).
Each pane spans the full terminal width. The `width` spec controls
height allocation (same `Fill`/`Px` proportional sizing).

    if ctx.width <= 84 && ctx.height > 45 then
        Layout.vertical [ commitsPane, diffPane ]
    else
        Layout.horizontal [ commitsPane, diffPane ]

-}
vertical : List (Pane msg) -> Layout msg
vertical panes =
    Vertical (List.map (\(PaneConstructor config) -> config) panes)


{-| Configuration for a tab within a pane group.
-}
type alias TabConfig msg =
    { id : String
    , label : String
    , content : PaneContent msg
    }


{-| Create a pane group with tabs — multiple content views sharing one
pane slot (like lazygit's Files/Worktrees/Submodules tabs). Only the
active tab's content is rendered. Each tab preserves its own scroll
and selection state in `Layout.State` (keyed by tab `id`).

Tab labels appear in the title bar, with the active tab bold and
inactive tabs dim (lazygit-style).

    Layout.paneGroup
        { tabs =
            [ { id = "files", label = "Files", content = filesList }
            , { id = "worktrees", label = "Worktrees", content = worktreesList }
            ]
        , activeTab = model.leftTab
        , width = Layout.fill
        }

Switch tabs by updating `activeTab` in your model (e.g., on `]`/`[` keys).

-}
paneGroup :
    String
    ->
        { tabs : List (TabConfig msg)
        , activeTab : String
        , width : Width
        }
    -> Pane msg
paneGroup groupId config =
    let
        activeContent : PaneContent msg
        activeContent =
            config.tabs
                |> List.filter (\tab -> tab.id == config.activeTab)
                |> List.head
                |> Maybe.map .content
                |> Maybe.withDefault (StaticContent [])

        -- Build styled title: active tab bold, inactive dim
        titleScreen : Screen
        titleScreen =
            config.tabs
                |> List.map
                    (\tab ->
                        if tab.id == config.activeTab then
                            Tui.text tab.label |> Tui.bold

                        else
                            Tui.text tab.label |> Tui.dim
                    )
                |> List.intersperse (Tui.text " - " |> Tui.dim)
                |> Tui.concat
    in
    PaneConstructor
        { id = groupId
        , title = ""
        , width = config.width
        , paneContent = activeContent
        , prefix = Nothing
        , footer = Nothing
        , titleScreen = Just titleScreen
        , footerScreen = Nothing
        , inlineFooter = Nothing
        , tabMapping = Just { activeTab = config.activeTab, tabIds = List.map .id config.tabs }
        }


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
        , footerScreen = Nothing
        , inlineFooter = Nothing
        , tabMapping = Nothing
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
        , maximizedPaneId = Nothing
        , activeTabMap = Dict.empty
        }


{-| Update the terminal dimensions in the state. Call this with the `Context`
from your `view` function.
-}
withContext : { a | width : Int, height : Int } -> State -> State
withContext ctx (State s) =
    State { s | context = { width = ctx.width, height = ctx.height } }


{-| Move selection down in a pane. Returns the updated state and fires
`onSelect` when the selection changes — the same message that click
produces. This means keyboard nav and mouse click are handled identically:

    -- In handleAction:
    DoNavigate direction ->
        let
            ( newLayout, maybeMsg ) =
                if direction > 0 then
                    Layout.navigateDown "commits" (myLayout model) model.layout
                else
                    Layout.navigateUp "commits" (myLayout model) model.layout
        in
        case maybeMsg of
            Just userMsg ->
                update userMsg { model | layout = newLayout }

            Nothing ->
                ( { model | layout = newLayout }, Effect.none )

Clamps at item bounds and auto-scrolls to keep the selection visible
with padding (lazygit-style). Returns `Nothing` when already at the
boundary (selection didn't change).

-}
navigateDown : String -> Layout msg -> State -> ( State, Maybe msg )
navigateDown paneId layout (State s) =
    let
        stateKey : String
        stateKey =
            resolveStateKey paneId layout

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState

        paneItemCount : Int
        paneItemCount =
            getItemCountForPane paneId layout

        visibleHeight : Int
        visibleHeight =
            s.context.height - 2

        newIndex : Int
        newIndex =
            min (max 0 (paneItemCount - 1)) (ps.selectedIndex + 1)

        scrollPadding : Int
        scrollPadding =
            2

        newOffset : Int
        newOffset =
            ensureVisible newIndex ps.scrollOffset visibleHeight paneItemCount scrollPadding

        selectionChanged : Bool
        selectionChanged =
            newIndex /= ps.selectedIndex
    in
    ( State
        { s
            | paneStates =
                Dict.insert stateKey
                    { selectedIndex = newIndex, scrollOffset = newOffset }
                    s.paneStates
            , activeTabMap =
                if stateKey /= paneId then
                    Dict.insert paneId stateKey s.activeTabMap

                else
                    s.activeTabMap
        }
    , if selectionChanged then
        getOnSelectForPane paneId layout
            |> Maybe.map (\onSelect -> onSelect newIndex)

      else
        Nothing
    )


{-| Move selection up in a pane. Returns the updated state and fires
`onSelect` when the selection changes. See `navigateDown` for usage.
-}
navigateUp : String -> Layout msg -> State -> ( State, Maybe msg )
navigateUp paneId layout (State s) =
    let
        stateKey : String
        stateKey =
            resolveStateKey paneId layout

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState

        paneItemCount : Int
        paneItemCount =
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
            ensureVisible newIndex ps.scrollOffset visibleHeight paneItemCount scrollPadding

        selectionChanged : Bool
        selectionChanged =
            newIndex /= ps.selectedIndex
    in
    ( State
        { s
            | paneStates =
                Dict.insert stateKey
                    { selectedIndex = newIndex, scrollOffset = newOffset }
                    s.paneStates
            , activeTabMap =
                if stateKey /= paneId then
                    Dict.insert paneId stateKey s.activeTabMap

                else
                    s.activeTabMap
        }
    , if selectionChanged then
        getOnSelectForPane paneId layout
            |> Maybe.map (\onSelect -> onSelect newIndex)

      else
        Nothing
    )


{-| Adjust scroll offset to keep an index visible within the viewport,
with scroll padding on each side (lazygit-style).
-}
ensureVisible : Int -> Int -> Int -> Int -> Int -> Int
ensureVisible index scrollOffset visibleHeight totalItems padding =
    let
        maxOffset : Int
        maxOffset =
            max 0 (totalItems - visibleHeight)
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


{-| Extract the onSelect callback for a pane from a Layout.
-}
getOnSelectForPane : String -> Layout msg -> Maybe (Int -> msg)
getOnSelectForPane paneId layout =
    findPane paneId layout
        |> Maybe.andThen
            (\p ->
                case p.paneContent of
                    SelectableContent { onSelect } ->
                        Just onSelect

                    StaticContent _ ->
                        Nothing
            )


{-| Get item count for a specific pane from a Layout.
-}
getItemCountForPane : String -> Layout msg -> Int
getItemCountForPane paneId layout =
    findPane paneId layout
        |> Maybe.map (\p -> contentLineCount p.paneContent)
        |> Maybe.withDefault 0


{-| Resolve a pane ID to the state key used for Dict lookups.
For regular panes, this is just the pane ID. For pane groups,
this resolves to the active tab's ID so each tab has its own
scroll/selection state.
-}
resolveStateKey : String -> Layout msg -> String
resolveStateKey paneId layout =
    findPane paneId layout
        |> Maybe.andThen .tabMapping
        |> Maybe.map .activeTab
        |> Maybe.withDefault paneId


{-| Find a pane config by id in any layout type.
-}
findPane : String -> Layout msg -> Maybe (PaneConfig msg)
findPane paneId layout =
    let
        panes =
            case layout of
                Horizontal ps ->
                    ps

                Vertical ps ->
                    ps
    in
    panes
        |> List.filter (\p -> p.id == paneId)
        |> List.head


{-| Get the currently selected index for a pane. For pane groups, pass the
group ID — the selection for the currently active tab is returned.
-}
selectedIndex : String -> State -> Int
selectedIndex paneId (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId
    in
    Dict.get stateKey s.paneStates
        |> Maybe.map .selectedIndex
        |> Maybe.withDefault 0


{-| Switch the active tab for a pane group. Updates the internal mapping
so that subsequent `selectedIndex`, `navigateDown`, etc. operate on the
new tab's state. Each tab's selection/scroll is preserved independently.

    Layout.switchTab "left" "worktrees" model.layout

-}
switchTab : String -> String -> State -> State
switchTab groupId tabId (State s) =
    State { s | activeTabMap = Dict.insert groupId tabId s.activeTabMap }


{-| Get the currently active tab ID for a pane group, or `Nothing` if
the group has never been navigated or doesn't exist.

    Layout.activeTab "left" model.layout
    -- → Just "files"

-}
activeTab : String -> State -> Maybe String
activeTab groupId (State s) =
    Dict.get groupId s.activeTabMap


{-| Set the selected index for a pane. Useful for restoring selection when
switching tabs, or programmatic navigation to a specific item.

    Layout.setSelectedIndex "modules" savedIndex model.layout

-}
setSelectedIndex : String -> Int -> State -> State
setSelectedIndex paneId index (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert stateKey
                    { ps | selectedIndex = max 0 index }
                    s.paneStates
        }


{-| Get the total item count for a pane. Useful for displaying "N of M" counters
without manually computing `List.length` on your items list.

    footer = String.fromInt (Layout.selectedIndex "list" state + 1)
        ++ " of "
        ++ String.fromInt (Layout.itemCount "list" layout)

-}
itemCount : String -> Layout msg -> Int
itemCount paneId layout =
    getItemCountForPane paneId layout


{-| Get the current scroll position for a pane.
-}
scrollPosition : String -> State -> Int
scrollPosition paneId (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId
    in
    Dict.get stateKey s.paneStates
        |> Maybe.map .scrollOffset
        |> Maybe.withDefault 0


{-| Get scroll information for a pane. Useful for rendering scroll
position indicators like "42%" or "120/280".

    info = Layout.scrollInfo "docs" layout model.layout
    -- { offset = 42, visible = 20, total = 280 }
    -- percentage = info.offset * 100 // info.total

-}
scrollInfo : String -> Layout msg -> State -> { offset : Int, visible : Int, total : Int }
scrollInfo paneId layout (State s) =
    let
        stateKey : String
        stateKey =
            resolveStateKey paneId layout
                |> (\resolved ->
                        if resolved /= paneId then
                            resolved

                        else
                            Dict.get paneId s.activeTabMap
                                |> Maybe.withDefault paneId
                   )

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState

        total : Int
        total =
            getItemCountForPane paneId layout

        visible : Int
        visible =
            s.context.height - 2
    in
    { offset = ps.scrollOffset
    , visible = visible
    , total = total
    }


{-| Reset scroll position for a pane to 0. Call when loading new content
(e.g., reset the diff scroll when selecting a different commit).
-}
resetScroll : String -> State -> State
resetScroll paneId (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert stateKey
                    { ps | scrollOffset = 0 }
                    s.paneStates
        }


{-| Scroll a pane down by the given number of lines.
-}
scrollDown : String -> Int -> State -> State
scrollDown paneId delta (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert stateKey
                    { ps | scrollOffset = ps.scrollOffset + delta }
                    s.paneStates
        }


{-| Scroll a pane up by the given number of lines.
-}
scrollUp : String -> Int -> State -> State
scrollUp paneId delta (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert stateKey
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


{-| Toggle a pane to full width (maximized), hiding siblings. Call again
to restore the split layout. Inspired by lazygit's Enter/full-screen
and tmux's Ctrl-z zoom.

    Layout.toggleMaximize "docs" model.layout

-}
toggleMaximize : String -> State -> State
toggleMaximize paneId (State s) =
    if s.maximizedPaneId == Just paneId then
        State { s | maximizedPaneId = Nothing }

    else
        State { s | maximizedPaneId = Just paneId }


{-| Check if a pane is currently maximized.
-}
isMaximized : String -> State -> Bool
isMaximized paneId (State s) =
    s.maximizedPaneId == Just paneId


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


{-| Set a styled Screen as the bottom border footer. Overrides the
plain-text footer from `withFooter`. Renders right-aligned on the
bottom border, like the string version but with styling.

    |> Layout.withFooterScreen
        (Tui.concat
            [ Tui.text (String.fromInt idx) |> Tui.bold
            , Tui.text " of " |> Tui.dim
            , Tui.text (String.fromInt total) |> Tui.bold
            ]
        )

-}
withFooterScreen : Screen -> Pane msg -> Pane msg
withFooterScreen screen (PaneConstructor config) =
    PaneConstructor { config | footerScreen = Just screen }


{-| Add an inline footer widget inside the pane border, below the content.
Renders above the bottom border — like lazygit's filter bar.

    Layout.pane "modules"
        { title = "Modules", width = Layout.fill }
        (Layout.selectableList { ... } items)
        |> Layout.withInlineFooter
            (Tui.concat
                [ Tui.text "Filter: " |> Tui.dim
                , Input.view { width = 20 } filterState
                ]
            )

The inline footer takes 1 row from the content area. If the pane is too
short for both content and footer, the footer is still shown.

-}
withInlineFooter : Screen -> Pane msg -> Pane msg
withInlineFooter screen (PaneConstructor config) =
    PaneConstructor { config | inlineFooter = Just screen }


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

        SelectableContent config ->
            config.itemCount


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
handleMouse mouseEvent ctx layout (State s) =
    let
        panes : List (PaneConfig msg)
        panes =
            case layout of
                Horizontal ps ->
                    ps

                Vertical ps ->
                    ps
    in
    handleMouseInternal mouseEvent ctx panes (State s)


handleMouseInternal : MouseEvent -> { width : Int, height : Int } -> List (PaneConfig msg) -> State -> ( State, Maybe msg )
handleMouseInternal mouseEvent ctx panes (State s) =
    let
        -- Persist context so contextOf returns correct values next time
        sWithCtx :
            { paneStates : Dict String PaneState
            , context : { width : Int, height : Int }
            , focusedPaneId : Maybe String
            , maximizedPaneId : Maybe String
            , activeTabMap : Dict String String
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
                        mouseStateKey : String
                        mouseStateKey =
                            config.tabMapping
                                |> Maybe.map .activeTab
                                |> Maybe.withDefault config.id

                        ps : PaneState
                        ps =
                            Dict.get mouseStateKey sWithCtx.paneStates
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
                                    Dict.insert mouseStateKey
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
                        mouseStateKey : String
                        mouseStateKey =
                            config.tabMapping
                                |> Maybe.map .activeTab
                                |> Maybe.withDefault config.id

                        ps : PaneState
                        ps =
                            Dict.get mouseStateKey sWithCtx.paneStates
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
                                    Dict.insert mouseStateKey
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
                                clickStateKey : String
                                clickStateKey =
                                    config.tabMapping
                                        |> Maybe.map .activeTab
                                        |> Maybe.withDefault config.id

                                contentRow : Int
                                contentRow =
                                    row - 1

                                ps : PaneState
                                ps =
                                    Dict.get clickStateKey sWithCtx.paneStates
                                        |> Maybe.withDefault defaultPaneState

                                clickedIndex : Int
                                clickedIndex =
                                    contentRow + ps.scrollOffset
                            in
                            ( State
                                { sWithCtx
                                    | paneStates =
                                        Dict.insert clickStateKey
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
toRows (State s) layout =
    case layout of
        Horizontal panes ->
            toRowsHorizontal s panes

        Vertical panes ->
            toRowsVertical s panes


toRowsHorizontal :
    { a | context : { width : Int, height : Int }, focusedPaneId : Maybe String, maximizedPaneId : Maybe String, paneStates : Dict String PaneState }
    -> List (PaneConfig msg)
    -> List Screen
toRowsHorizontal s panes =
    let
        -- When a pane is maximized, only show that pane at full width
        visiblePanes : List (PaneConfig msg)
        visiblePanes =
            case s.maximizedPaneId of
                Just maxId ->
                    panes |> List.filter (\p -> p.id == maxId)

                Nothing ->
                    panes

        totalWidth : Int
        totalWidth =
            s.context.width

        totalHeight : Int
        totalHeight =
            s.context.height

        -- Reserve 1 column per gap between panes (paneCount - 1 gaps)
        gapCount : Int
        gapCount =
            max 0 (List.length visiblePanes - 1)

        widths : List Int
        widths =
            resolveWidths (totalWidth - gapCount) (List.map .width visiblePanes)

        panesWithWidths : List ( PaneConfig msg, Int )
        panesWithWidths =
            List.map2 Tuple.pair visiblePanes widths

        paneCount : Int
        paneCount =
            List.length visiblePanes

        renderRow : Int -> Screen
        renderRow row =
            Tui.concat
                (panesWithWidths
                    |> List.indexedMap
                        (\paneIdx ( paneConfig, w ) ->
                            let
                                innerW : Int
                                innerW =
                                    w - 2

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
                                                Tui.truncateWidth (innerW - 1) screen

                                            Nothing ->
                                                Tui.styled borderStyle titleText

                                    titleWidth : Int
                                    titleWidth =
                                        case paneConfig.titleScreen of
                                            Just screen ->
                                                String.length (Tui.toString (Tui.truncateWidth (innerW - 1) screen))

                                            Nothing ->
                                                String.length titleText

                                    -- Account for prefix dash(es): ╭─ for first, ─ for non-first
                                    prefixWidth : Int
                                    prefixWidth =
                                        if isFirstPane then
                                            1

                                        else
                                            1

                                    fillLen : Int
                                    fillLen =
                                        max 0 (innerW - titleWidth - prefixWidth)

                                    gap : Screen
                                    gap =
                                        if isFirstPane then
                                            Tui.empty

                                        else
                                            Tui.text " "
                                in
                                Tui.concat
                                    [ gap
                                    , Tui.styled borderStyle "╭─"
                                    , titleContent
                                    , Tui.styled borderStyle (String.repeat fillLen "─")
                                    , Tui.styled borderStyle "╮"
                                    ]

                            else if row == totalHeight - 1 then
                                let
                                    footerContent : Screen
                                    footerContent =
                                        case paneConfig.footerScreen of
                                            Just screen ->
                                                screen

                                            Nothing ->
                                                case paneConfig.footer of
                                                    Just ft ->
                                                        Tui.styled borderStyle ft

                                                    Nothing ->
                                                        Tui.empty

                                    footerLen : Int
                                    footerLen =
                                        String.length (Tui.toString footerContent)

                                    dashLen : Int
                                    dashLen =
                                        max 0 (innerW - footerLen)
                                in
                                let
                                    gap : Screen
                                    gap =
                                        if isFirstPane then
                                            Tui.empty

                                        else
                                            Tui.text " "
                                in
                                Tui.concat
                                    [ gap
                                    , Tui.styled borderStyle "╰"
                                    , Tui.styled borderStyle (String.repeat dashLen "─")
                                    , if footerLen > 0 then
                                        footerContent

                                      else
                                        Tui.empty
                                    , Tui.styled borderStyle "╯"
                                    ]

                            else if paneConfig.inlineFooter /= Nothing && row == totalHeight - 2 then
                                -- Inline footer: render widget on the last content row
                                let
                                    footerScreen : Screen
                                    footerScreen =
                                        paneConfig.inlineFooter |> Maybe.withDefault Tui.empty

                                    footerText : String
                                    footerText =
                                        Tui.toString footerScreen

                                    footerWidth : Int
                                    footerWidth =
                                        String.length footerText

                                    padding : Int
                                    padding =
                                        max 0 (innerW - footerWidth)
                                in
                                Tui.concat
                                    [ Tui.styled borderStyle "│"
                                    , Tui.truncateWidth innerW footerScreen
                                    , Tui.text (String.repeat padding " ")
                                    , Tui.styled borderStyle "│"
                                    ]

                            else
                                let
                                    renderStateKey : String
                                    renderStateKey =
                                        paneConfig.tabMapping
                                            |> Maybe.map .activeTab
                                            |> Maybe.withDefault paneConfig.id

                                    ps : PaneState
                                    ps =
                                        Dict.get renderStateKey s.paneStates
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
                                let
                                    gap : Screen
                                    gap =
                                        if isFirstPane then
                                            Tui.empty

                                        else
                                            Tui.text " "
                                in
                                Tui.concat
                                    [ gap
                                    , Tui.styled borderStyle "│"
                                    , truncatedLine
                                    , paddingScreen
                                    , scrollbarBorder borderStyle paneConfig.paneContent ps contentRow totalHeight
                                    ]
                        )
                )
    in
    List.range 0 (totalHeight - 1)
        |> List.map renderRow


toRowsVertical :
    { a | context : { width : Int, height : Int }, focusedPaneId : Maybe String, maximizedPaneId : Maybe String, paneStates : Dict String PaneState }
    -> List (PaneConfig msg)
    -> List Screen
toRowsVertical s panes =
    let
        totalWidth : Int
        totalWidth =
            s.context.width

        totalHeight : Int
        totalHeight =
            s.context.height

        innerW : Int
        innerW =
            totalWidth - 2

        heights : List Int
        heights =
            resolveWidths totalHeight (List.map .width panes)

        paneCount : Int
        paneCount =
            List.length panes

        renderPane : Int -> PaneConfig msg -> Int -> List Screen
        renderPane paneIdx paneConfig paneHeight =
            let
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

                vertStateKey : String
                vertStateKey =
                    paneConfig.tabMapping
                        |> Maybe.map .activeTab
                        |> Maybe.withDefault paneConfig.id

                ps : PaneState
                ps =
                    Dict.get vertStateKey s.paneStates
                        |> Maybe.withDefault defaultPaneState

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
                    String.length (Tui.toString titleContent)

                fillLen : Int
                fillLen =
                    max 0 (innerW - titleWidth)

                topBorder : Screen
                topBorder =
                    Tui.concat
                        [ Tui.styled borderStyle
                            (if isFirstPane then
                                "╭"

                             else
                                "├"
                            )
                        , titleContent
                        , Tui.styled borderStyle (String.repeat fillLen "─")
                        , Tui.styled borderStyle
                            (if isFirstPane then
                                "╮"

                             else
                                "┤"
                            )
                        ]

                bottomBorder : Screen
                bottomBorder =
                    let
                        footerContent : Screen
                        footerContent =
                            case paneConfig.footerScreen of
                                Just screen ->
                                    screen

                                Nothing ->
                                    case paneConfig.footer of
                                        Just ft ->
                                            Tui.styled borderStyle ft

                                        Nothing ->
                                            Tui.empty

                        footerLen : Int
                        footerLen =
                            String.length (Tui.toString footerContent)

                        dashLen : Int
                        dashLen =
                            max 0 (innerW - footerLen)
                    in
                    Tui.concat
                        [ Tui.styled borderStyle "╰"
                        , Tui.styled borderStyle (String.repeat dashLen "─")
                        , if footerLen > 0 then
                            footerContent

                          else
                            Tui.empty
                        , Tui.styled borderStyle "╯"
                        ]

                -- Content rows: top border + content, last pane also gets bottom border
                numContentRows : Int
                numContentRows =
                    if isLastPane then
                        paneHeight - 2

                    else
                        paneHeight - 1

                contentRows : List Screen
                contentRows =
                    List.range 0 (numContentRows - 1)
                        |> List.map
                            (\contentRow ->
                                let
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
                                            Tui.styled (Tui.extractStyle lineScreen) (String.repeat padding " ")

                                        else
                                            Tui.text (String.repeat padding " ")
                                in
                                Tui.concat
                                    [ Tui.styled borderStyle "│"
                                    , truncatedLine
                                    , paddingScreen
                                    , Tui.styled borderStyle "│"
                                    ]
                            )
            in
            if isLastPane then
                topBorder :: contentRows ++ [ bottomBorder ]

            else
                topBorder :: contentRows
    in
    List.map3 renderPane
        (List.range 0 (paneCount - 1))
        panes
        heights
        |> List.concat


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
