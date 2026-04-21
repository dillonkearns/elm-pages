module Tui.Layout exposing
    ( Layout, Pane, horizontal, vertical, pane, paneGroup, TabConfig
    , PaneContent, content, selectableList, SelectionState(..), indexSelectableList, withUnfocusedStyle, withFilterable, withSearchable, withTreeView
    , Modal, promptModal, confirmModal, pickerModal, menuModal, helpModal
    , Group, Binding, group, binding, charBinding
    , Width, fill, fillPortion, fixed
    , State, init, withContext
    , navigateDown, navigateUp, pageDown, pageUp, selectedIndex, selectedItem, setSelectedIndex, itemCount, scrollPosition, scrollInfo, resetScroll, scrollDown, scrollUp, contextOf
    , switchTab, activeTab
    , focusPane, focusedPane
    , setSearching
    , handleKeyEvent
    , toggleMaximize, isMaximized
    , withPrefix, withFooter, withTitleScreen, withFooterScreen, withInlineFooter, withOnScroll, withOnLinkClick
    , handleMouse
    , toScreen, toRows
    , navigationHelpRows
    , isFilterActive, filterStatusBar, activeFilterStatusBar
    , isSearchActive, searchStatusBar
    , compileApp, FrameworkModel, FrameworkMsg
    , frameworkFocusedPane, frameworkSelectedIndex, frameworkScrollPosition, frameworkUserModel
    , RawEvent(..), ScrollDirection(..)
    , UpdateContext
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
                    { onSelect = \c -> SelectCommit c
                    , view =
                        \{ selection } c ->
                            case selection of
                                Layout.Selected { focused } ->
                                    TuiScreen.text ("▸ " ++ c.sha)
                                        |> (if focused then
                                                TuiScreen.bold

                                            else
                                                identity
                                           )

                                Layout.NotSelected ->
                                    TuiScreen.text ("  " ++ c.sha)
                    }
                    model.commits
                )
            ]
            |> Layout.toScreen (Layout.withContext ctx model.layout)

For a batteries-included setup that wires key routing, focus management,
modals, and status together automatically, see [`compileApp`](#compileApp).


## Building Layouts

@docs Layout, Pane, horizontal, vertical, pane, paneGroup, TabConfig


## Pane Content

@docs PaneContent, content, selectableList, SelectionState, indexSelectableList, withUnfocusedStyle, withFilterable, withSearchable, withTreeView


## Modals

Declarative modals powered by [`Tui.Modal`](Tui-Modal), [`Tui.Picker`](Tui-Picker),
[`Tui.Menu`](Tui-Menu), [`Tui.Confirm`](Tui-Confirm), and [`Tui.Prompt`](Tui-Prompt).
These are convenience wrappers for use with [`compileApp`](#compileApp) — the framework
handles opening, closing, and key routing automatically.

@docs Modal, promptModal, confirmModal, pickerModal, menuModal, helpModal


## Keybindings

Declare keybinding groups for dispatch and auto-generated help.
See [`Tui.Keybinding`](Tui-Keybinding) for the standalone keybinding system.

@docs Group, Binding, group, binding, charBinding


## Pane Width

@docs Width, fill, fillPortion, fixed


## State

@docs State, init, withContext


## Selection & Scrolling

@docs navigateDown, navigateUp, pageDown, pageUp, selectedIndex, selectedItem, setSelectedIndex, itemCount, scrollPosition, scrollInfo, resetScroll, scrollDown, scrollUp, contextOf


## Tabs

@docs switchTab, activeTab


## Focus & Interaction

@docs focusPane, focusedPane
@docs setSearching
@docs handleKeyEvent
@docs toggleMaximize, isMaximized


## Pane Decoration

@docs withPrefix, withFooter, withTitleScreen, withFooterScreen, withInlineFooter, withOnScroll, withOnLinkClick


## Mouse

@docs handleMouse


## Rendering

@docs toScreen, toRows


## Help & Status Bars

@docs navigationHelpRows

@docs isFilterActive, filterStatusBar, activeFilterStatusBar
@docs isSearchActive, searchStatusBar


## compileApp — Batteries-Included Framework

[`compileApp`](#compileApp) wires together key routing, focus management (Tab/Shift-Tab),
j/k/arrow navigation, scroll, mouse dispatch, modals, status toasts, and the
options bar — so your app only needs `init`, `update`, `view`, `bindings`,
`status`, and `modal`.

@docs compileApp, FrameworkModel, FrameworkMsg

@docs frameworkFocusedPane, frameworkSelectedIndex, frameworkScrollPosition, frameworkUserModel

@docs RawEvent, ScrollDirection

@docs UpdateContext

-}

import Ansi.Color
import Array
import BackendTask exposing (BackendTask)
import Char
import Dict exposing (Dict)
import FatalError exposing (FatalError)
import Set exposing (Set)
import String.Graphemes as Graphemes
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Keybinding
import Tui.Layout.Effect.Internal as LayoutEffect
import Tui.Menu
import Tui.Modal
import Tui.OptionsBar
import Tui.Prompt
import Tui.Screen as TuiScreen exposing (Screen)
import Tui.Screen.Advanced as TuiScreenAdvanced
import Tui.Status
import Tui.Sub exposing (MouseEvent)


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
    , tabClickHandler : Maybe { onTabClick : String -> msg, tabLabels : List { id : String, label : String } }
    , onScroll : Maybe (Int -> msg)
    , onLinkClick : Maybe (String -> msg)
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
    = StaticContent { lines : Array.Array Screen, lineCount : Int, searchable : Bool }
    | SelectableContent
        { itemCount : Int
        , renderItem :
            Int
            -> Screen -- renders default view for item at index
        , renderSelected :
            Int
            -> Screen -- renders selected view for item at index
        , renderSelectedUnfocused :
            Int
            -> Screen -- renders selected view when pane is unfocused
        , onSelect : Int -> msg
        , filterText : Maybe (Int -> String)
        , treeConfig : Maybe { toPath : Int -> List String }
        }


{-| Width specification using integer weights (like elm-ui).
-}
type Width
    = Fill Int
    | Fixed Int


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
        , searching : Bool
        , filterStates : Dict String FilterState
        , searchStates : Dict String SearchState
        , treeStates : Dict String TreeState
        }


type alias TreeState =
    { showTree : Bool
    , collapsedPaths : Set String
    }


type FilterMode
    = FilterTyping
    | FilterApplied


type alias FilterState =
    { query : String
    , mode : FilterMode
    , filteredIndices : List Int
    }


type SearchMode
    = SearchTyping
    | SearchCommitted


type alias SearchState =
    { query : String
    , mode : SearchMode
    , matchPositions : List { line : Int, col : Int, len : Int }
    , currentMatchIndex : Int
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
height allocation (same `Fill`/`Fixed` proportional sizing).

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
        , onTabClick : Maybe (String -> msg)
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
                |> Maybe.withDefault (StaticContent { lines = Array.empty, lineCount = 0, searchable = False })

        -- Build styled title: active tab bold, inactive dim
        titleScreen : Screen
        titleScreen =
            config.tabs
                |> List.map
                    (\tab ->
                        if tab.id == config.activeTab then
                            TuiScreen.text tab.label |> TuiScreen.bold

                        else
                            TuiScreen.text tab.label |> TuiScreen.dim
                    )
                |> List.intersperse (TuiScreen.text " - " |> TuiScreen.dim)
                |> TuiScreen.concat
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
        , tabClickHandler =
            config.onTabClick
                |> Maybe.map
                    (\handler ->
                        { onTabClick = handler
                        , tabLabels = List.map (\tab -> { id = tab.id, label = tab.label }) config.tabs
                        }
                    )
        , onScroll = Nothing
        , onLinkClick = Nothing
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
        , tabClickHandler = Nothing
        , onScroll = Nothing
        , onLinkClick = Nothing
        }


{-| Static content — a list of screens, one per line. No selection behavior.
-}
content : List Screen -> PaneContent msg
content lines =
    StaticContent { lines = Array.fromList lines, lineCount = List.length lines, searchable = False }


{-| Index-based selectable list. Prefer [`selectableList`](#selectableList) for
new code — the item-based `onSelect` eliminates index-mapping bugs.

    Layout.indexSelectableList
        { onSelect = SelectCommitIndex
        , selected = \commit -> TuiScreen.text commit.sha |> TuiScreen.bg Ansi.Color.blue
        , default = \commit -> TuiScreen.text commit.sha
        }
        model.commits

-}
indexSelectableList :
    { onSelect : Int -> msg
    , selected : item -> Screen
    , default : item -> Screen
    }
    -> List item
    -> PaneContent msg
indexSelectableList config items =
    let
        itemArray : Array.Array item
        itemArray =
            Array.fromList items
    in
    let
        renderSel : Int -> Screen
        renderSel =
            \i ->
                Array.get i itemArray
                    |> Maybe.map config.selected
                    |> Maybe.withDefault TuiScreen.empty
    in
    SelectableContent
        { itemCount = Array.length itemArray
        , renderItem =
            \i ->
                Array.get i itemArray
                    |> Maybe.map config.default
                    |> Maybe.withDefault TuiScreen.empty
        , renderSelected = renderSel
        , renderSelectedUnfocused = renderSel
        , onSelect = config.onSelect
        , filterText = Nothing
        , treeConfig = Nothing
        }


{-| Set a different render style for the selected item when the pane is
unfocused. In lazygit, the focused pane shows the selection with a blue
background, while unfocused panes show it dimmed (bold only).

Without this, unfocused panes use the same `selected` style as focused ones.

    Layout.selectableList
        { onSelect = SelectItem
        , selected = \item -> TuiScreen.text ("▸ " ++ item) |> TuiScreen.bg Ansi.Color.blue
        , default = \item -> TuiScreen.text ("  " ++ item)
        }
        items
        |> Layout.withUnfocusedStyle
            (\item -> TuiScreen.text ("▸ " ++ item) |> TuiScreen.bold)
            items

-}
withUnfocusedStyle : (item -> Screen) -> List item -> PaneContent msg -> PaneContent msg
withUnfocusedStyle renderUnfocused items paneContent =
    case paneContent of
        SelectableContent config ->
            let
                itemArray : Array.Array item
                itemArray =
                    Array.fromList items
            in
            SelectableContent
                { config
                    | renderSelectedUnfocused =
                        \i ->
                            Array.get i itemArray
                                |> Maybe.map renderUnfocused
                                |> Maybe.withDefault TuiScreen.empty
                }

        StaticContent _ ->
            paneContent


{-| The selection state of an item in a selectable list.

  - `Selected { focused = True }` — this item is selected AND the pane is focused
  - `Selected { focused = False }` — this item is selected but the pane is unfocused
  - `NotSelected` — this item is not selected

Use `Selected _` to match any selected item regardless of focus.

    Layout.selectableList
        { onSelect = \commit -> SelectCommit commit
        , view =
            \{ selection } commit ->
                case selection of
                    Layout.Selected { focused } ->
                        TuiScreen.text commit.sha
                            |> (if focused then
                                    TuiScreen.bg Ansi.Color.blue

                                else
                                    TuiScreen.bold
                               )

                    Layout.NotSelected ->
                        TuiScreen.text commit.sha
        }
        model.commits

-}
type SelectionState
    = Selected { focused : Bool }
    | NotSelected


{-| A selectable list with item-based `onSelect` and a unified view function
that receives `SelectionState`.

    Layout.selectableList
        { onSelect = \item -> SelectItem item
        , view =
            \{ selection } item ->
                case selection of
                    Layout.Selected { focused } ->
                        TuiScreen.text item
                            |> (if focused then
                                    TuiScreen.bg Ansi.Color.blue

                                else
                                    TuiScreen.bold
                               )

                    Layout.NotSelected ->
                        TuiScreen.text item
        }
        items

For an index-based variant, see [`indexSelectableList`](#indexSelectableList).

-}
selectableList :
    { onSelect : item -> msg
    , view : { selection : SelectionState } -> item -> Screen
    }
    -> List item
    -> PaneContent msg
selectableList config items =
    case items of
        [] ->
            -- Empty list: no selection behavior, no onSelect to fire
            StaticContent { lines = Array.empty, lineCount = 0, searchable = False }

        first :: _ ->
            let
                itemArray : Array.Array item
                itemArray =
                    Array.fromList items

                renderWith : SelectionState -> Int -> Screen
                renderWith selState i =
                    Array.get i itemArray
                        |> Maybe.map (config.view { selection = selState })
                        |> Maybe.withDefault TuiScreen.empty
            in
            SelectableContent
                { itemCount = Array.length itemArray
                , renderItem = renderWith NotSelected
                , renderSelected = renderWith (Selected { focused = True })
                , renderSelectedUnfocused = renderWith (Selected { focused = False })
                , onSelect =
                    \i ->
                        Array.get i itemArray
                            |> Maybe.withDefault first
                            |> config.onSelect
                , filterText = Nothing
                , treeConfig = Nothing
                }



-- MODAL


{-| A modal dialog configuration. The framework manages the internal interaction
state (input text, cursor, picker filter, menu highlight). You just describe
the modal and receive semantic messages.

    modal : Model -> Maybe (Layout.Modal Msg)
    modal model =
        case model.modal of
            Just CommitDialog ->
                Just
                    (Layout.promptModal
                        { title = "Commit Message"
                        , initialValue = ""
                        , onSubmit = SubmitCommit
                        , onCancel = CloseModal
                        }
                    )

            Nothing ->
                Nothing

-}
type Modal msg
    = PromptModal
        { title : String
        , initialValue : String
        , onSubmit : String -> msg
        , onCancel : msg
        }
    | ConfirmModal
        { title : String
        , message : String
        , onConfirm : msg
        , onCancel : msg
        }
    | PickerModal
        { labels : List String
        , title : String
        , onSelectIndex : Int -> msg
        , onCancel : msg
        }
    | MenuModal (List (Tui.Menu.Section msg))
    | HelpModal msg


{-| A text input modal. The framework manages the input state (cursor,
typing). You receive the final value on submit.

    Layout.promptModal
        { title = "Commit Message"
        , initialValue = ""
        , onSubmit = SubmitCommit
        , onCancel = CloseModal
        }

-}
promptModal : { title : String, initialValue : String, onSubmit : String -> msg, onCancel : msg } -> Modal msg
promptModal =
    PromptModal


{-| A yes/no confirmation dialog. The framework handles Enter/Escape routing.

    Layout.confirmModal
        { title = "Reset changes?"
        , message = "This will discard all uncommitted changes."
        , onConfirm = ResetChanges
        , onCancel = CloseModal
        }

-}
confirmModal : { title : String, message : String, onConfirm : msg, onCancel : msg } -> Modal msg
confirmModal =
    ConfirmModal


{-| A picker modal with filter/fuzzy match. The framework manages filter
state, selection, and scrolling. Items can be any type.

    Layout.pickerModal
        { items = allPackageNames
        , toString = identity
        , title = "Browse Package"
        , onSelect = \pkg -> BrowsePackage pkg
        , onCancel = CloseModal
        }

-}
pickerModal : { items : List item, toString : item -> String, title : String, onSelect : item -> msg, onCancel : msg } -> Modal msg
pickerModal config =
    let
        itemArray : Array.Array item
        itemArray =
            Array.fromList config.items
    in
    PickerModal
        { labels = List.map config.toString config.items
        , title = config.title
        , onSelectIndex =
            \i ->
                Array.get i itemArray
                    |> Maybe.map config.onSelect
                    |> Maybe.withDefault config.onCancel
        , onCancel = config.onCancel
        }


{-| A menu modal with sections and direct key dispatch (like lazygit's
context menu). The framework manages j/k highlight and Enter confirm.

    Layout.menuModal
        [ Menu.section "Files"
            [ Menu.item { key = Tui.Sub.Character 's', label = "Stage", action = StageFile }
            ]
        ]

-}
menuModal : List (Tui.Menu.Section msg) -> Modal msg
menuModal =
    MenuModal


{-| A help modal auto-generated from the app's bindings. Shows all keybindings
with searchable filtering.

    Layout.helpModal CloseModal

The `onClose` message fires when the user presses Escape.

-}
helpModal : msg -> Modal msg
helpModal onClose =
    HelpModal onClose



-- BINDING HELPERS


{-| A group of keybindings with a section name. Re-exported from
[`Tui.Keybinding.Group`](Tui-Keybinding#Group) for convenience.
-}
type alias Group msg =
    Tui.Keybinding.Group msg


{-| A single keybinding. Re-exported from
[`Tui.Keybinding.Binding`](Tui-Keybinding#Binding) for convenience.
-}
type alias Binding msg =
    Tui.Keybinding.Binding msg


{-| Create a named group of bindings.

    Layout.group "Actions"
        [ Layout.charBinding 'c' "Commit" OpenCommitDialog
        , Layout.binding Tui.Sub.Enter "Confirm" Confirm
        ]

-}
group : String -> List (Binding msg) -> Group msg
group =
    Tui.Keybinding.group


{-| Create a binding with any [`Tui.Sub.Key`](Tui#Key).

    Layout.binding (Tui.Sub.Character 'c') "Commit" OpenCommitDialog

    Layout.binding Tui.Sub.Enter "Confirm" Confirm

    Layout.binding (Tui.Sub.FunctionKey 5) "Refresh" Refresh

For a shorthand that takes a `Char`, see [`charBinding`](#charBinding).

-}
binding : Tui.Sub.Key -> String -> msg -> Binding msg
binding =
    Tui.Keybinding.binding


{-| Create a binding with a single character key (no modifiers).
Shorthand for `binding (Tui.Sub.Character c) desc action`.

    Layout.charBinding 'c' "Commit" OpenCommitDialog

    Layout.charBinding 'q' "Quit" Quit

-}
charBinding : Char -> String -> msg -> Binding msg
charBinding char desc action =
    Tui.Keybinding.binding (Tui.Sub.Character char) desc action


{-| Make static content searchable. When the pane is focused, pressing `/`
opens a search prompt (lazygit-style). Results are highlighted with
cyan (current match) and yellow (other matches).

    Layout.content diffLines
        |> Layout.withSearchable

-}
withSearchable : PaneContent msg -> PaneContent msg
withSearchable paneContent =
    case paneContent of
        StaticContent rec ->
            StaticContent { rec | searchable = True }

        SelectableContent _ ->
            paneContent


{-| Make a selectable list filterable. When the pane is focused, pressing `/`
opens a filter input (lazygit-style). Items are matched using smart-case
substring matching.

    Layout.selectableList
        { onSelect = SelectItem
        , selected = \item -> TuiScreen.text ("▸ " ++ item)
        , default = \item -> TuiScreen.text ("  " ++ item)
        }
        items
        |> Layout.withFilterable identity

The first argument converts an item to its searchable text. The second
argument is the same items list (needed because `PaneContent` erases the
item type).

-}
withFilterable : (item -> String) -> List item -> PaneContent msg -> PaneContent msg
withFilterable toText items paneContent =
    case paneContent of
        SelectableContent config ->
            let
                itemArray : Array.Array item
                itemArray =
                    Array.fromList items
            in
            SelectableContent
                { config
                    | filterText =
                        Just
                            (\i ->
                                Array.get i itemArray
                                    |> Maybe.map toText
                                    |> Maybe.withDefault ""
                            )
                }

        StaticContent _ ->
            paneContent


{-| Enable lazygit-style tree view on a selectable list. Items are grouped
by path segments and displayed as a collapsible directory tree.

    Layout.selectableList
        { onSelect = SelectFile
        , selected = \f -> TuiScreen.text ("▸ " ++ f)
        , default = \f -> TuiScreen.text ("  " ++ f)
        }
        files
        |> Layout.withTreeView
            { toPath = String.split "/" }

The `toPath` function splits each item into path segments used for tree
grouping. Single-child directory chains are compressed (e.g., `src/Api`
becomes one node).

Built-in keybindings when tree view is active:

  - `` ` `` — toggle between tree and flat view
  - `-` — collapse all directories
  - `=` — expand all directories
  - `Enter` — toggle collapse on a directory node

-}
withTreeView : { toPath : item -> List String } -> List item -> PaneContent msg -> PaneContent msg
withTreeView config items paneContent =
    case paneContent of
        SelectableContent selConfig ->
            let
                itemArray : Array.Array item
                itemArray =
                    Array.fromList items
            in
            SelectableContent
                { selConfig
                    | treeConfig =
                        Just
                            { toPath =
                                \i ->
                                    Array.get i itemArray
                                        |> Maybe.map config.toPath
                                        |> Maybe.withDefault []
                            }
                }

        StaticContent _ ->
            paneContent



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


{-| Fixed column width. Specifies an exact number of terminal cells.
-}
fixed : Int -> Width
fixed =
    Fixed



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
        , searching = False
        , filterStates = Dict.empty
        , searchStates = Dict.empty
        , treeStates = Dict.empty
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

        filterState : Maybe FilterState
        filterState =
            Dict.get stateKey s.filterStates

        maybeTreeConfig : Maybe { toPath : Int -> List String }
        maybeTreeConfig =
            getTreeConfigForPane paneId layout

        treeState : Maybe TreeState
        treeState =
            case maybeTreeConfig of
                Just _ ->
                    Just (Dict.get stateKey s.treeStates |> Maybe.withDefault defaultTreeState)

                Nothing ->
                    Nothing

        treeRows : Maybe (List TreeRow)
        treeRows =
            case ( maybeTreeConfig, treeState ) of
                ( Just tc, Just ts ) ->
                    if ts.showTree then
                        Just (buildTreeRows tc.toPath (countTreeItems tc.toPath 0) ts)

                    else
                        Nothing

                _ ->
                    Nothing

        effectiveItemCount : Int
        effectiveItemCount =
            case treeRows of
                Just rows ->
                    List.length rows

                Nothing ->
                    case filterState of
                        Just fs ->
                            List.length fs.filteredIndices

                        Nothing ->
                            getItemCountForPane paneId layout

        visibleHeight : Int
        visibleHeight =
            s.context.height - 2

        newIndex : Int
        newIndex =
            min (max 0 (effectiveItemCount - 1)) (ps.selectedIndex + 1)

        scrollPadding : Int
        scrollPadding =
            2

        newOffset : Int
        newOffset =
            ensureVisible newIndex ps.scrollOffset visibleHeight effectiveItemCount scrollPadding

        selectionChanged : Bool
        selectionChanged =
            newIndex /= ps.selectedIndex

        originalIndex : Int
        originalIndex =
            case treeRows of
                Just rows ->
                    rows
                        |> List.drop newIndex
                        |> List.head
                        |> Maybe.andThen .originalIndex
                        |> Maybe.withDefault -1

                Nothing ->
                    mapFilteredIndex newIndex filterState

        -- For tree view, don't fire onSelect for directory nodes
        shouldFireOnSelect : Bool
        shouldFireOnSelect =
            case treeRows of
                Just rows ->
                    rows
                        |> List.drop newIndex
                        |> List.head
                        |> Maybe.map (\row -> not row.isDirectory)
                        |> Maybe.withDefault False

                Nothing ->
                    True
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
    , if selectionChanged && shouldFireOnSelect && originalIndex >= 0 then
        getOnSelectForPane paneId layout
            |> Maybe.map (\onSelect -> onSelect originalIndex)

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

        filterState : Maybe FilterState
        filterState =
            Dict.get stateKey s.filterStates

        maybeTreeConfig : Maybe { toPath : Int -> List String }
        maybeTreeConfig =
            getTreeConfigForPane paneId layout

        treeState : Maybe TreeState
        treeState =
            case maybeTreeConfig of
                Just _ ->
                    Just (Dict.get stateKey s.treeStates |> Maybe.withDefault defaultTreeState)

                Nothing ->
                    Nothing

        treeRows : Maybe (List TreeRow)
        treeRows =
            case ( maybeTreeConfig, treeState ) of
                ( Just tc, Just ts ) ->
                    if ts.showTree then
                        Just (buildTreeRows tc.toPath (countTreeItems tc.toPath 0) ts)

                    else
                        Nothing

                _ ->
                    Nothing

        effectiveItemCount : Int
        effectiveItemCount =
            case treeRows of
                Just rows ->
                    List.length rows

                Nothing ->
                    case filterState of
                        Just fs ->
                            List.length fs.filteredIndices

                        Nothing ->
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
            ensureVisible newIndex ps.scrollOffset visibleHeight effectiveItemCount scrollPadding

        selectionChanged : Bool
        selectionChanged =
            newIndex /= ps.selectedIndex

        originalIndex : Int
        originalIndex =
            case treeRows of
                Just rows ->
                    rows
                        |> List.drop newIndex
                        |> List.head
                        |> Maybe.andThen .originalIndex
                        |> Maybe.withDefault -1

                Nothing ->
                    mapFilteredIndex newIndex filterState

        shouldFireOnSelect : Bool
        shouldFireOnSelect =
            case treeRows of
                Just rows ->
                    rows
                        |> List.drop newIndex
                        |> List.head
                        |> Maybe.map (\row -> not row.isDirectory)
                        |> Maybe.withDefault False

                Nothing ->
                    True
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
    , if selectionChanged && shouldFireOnSelect && originalIndex >= 0 then
        getOnSelectForPane paneId layout
            |> Maybe.map (\onSelect -> onSelect originalIndex)

      else
        Nothing
    )


{-| Move selection down by one page (viewport height). Like lazygit's
PgDn behavior — the selection jumps by the visible height, keeping
the scroll-off margin.
-}
pageDown : String -> Layout msg -> State -> ( State, Maybe msg )
pageDown paneId layout (State s) =
    let
        stateKey : String
        stateKey =
            resolveStateKey paneId layout

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState

        filterState : Maybe FilterState
        filterState =
            Dict.get stateKey s.filterStates

        effectiveItemCount : Int
        effectiveItemCount =
            case filterState of
                Just fs ->
                    List.length fs.filteredIndices

                Nothing ->
                    getItemCountForPane paneId layout

        visibleHeight : Int
        visibleHeight =
            s.context.height - 2

        newIndex : Int
        newIndex =
            min (max 0 (effectiveItemCount - 1)) (ps.selectedIndex + visibleHeight)

        scrollPadding : Int
        scrollPadding =
            2

        newOffset : Int
        newOffset =
            ensureVisible newIndex ps.scrollOffset visibleHeight effectiveItemCount scrollPadding

        selectionChanged : Bool
        selectionChanged =
            newIndex /= ps.selectedIndex

        originalIndex : Int
        originalIndex =
            mapFilteredIndex newIndex filterState
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
            |> Maybe.map (\onSelect -> onSelect originalIndex)

      else
        Nothing
    )


{-| Move selection up by one page (viewport height). Like lazygit's
PgUp behavior.
-}
pageUp : String -> Layout msg -> State -> ( State, Maybe msg )
pageUp paneId layout (State s) =
    let
        stateKey : String
        stateKey =
            resolveStateKey paneId layout

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState

        filterState : Maybe FilterState
        filterState =
            Dict.get stateKey s.filterStates

        effectiveItemCount : Int
        effectiveItemCount =
            case filterState of
                Just fs ->
                    List.length fs.filteredIndices

                Nothing ->
                    getItemCountForPane paneId layout

        visibleHeight : Int
        visibleHeight =
            s.context.height - 2

        newIndex : Int
        newIndex =
            max 0 (ps.selectedIndex - visibleHeight)

        scrollPadding : Int
        scrollPadding =
            2

        newOffset : Int
        newOffset =
            ensureVisible newIndex ps.scrollOffset visibleHeight effectiveItemCount scrollPadding

        selectionChanged : Bool
        selectionChanged =
            newIndex /= ps.selectedIndex

        originalIndex : Int
        originalIndex =
            mapFilteredIndex newIndex filterState
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
            |> Maybe.map (\onSelect -> onSelect originalIndex)

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


isContentPaneId : String -> Layout msg -> Bool
isContentPaneId paneId layout =
    findPane paneId layout
        |> Maybe.map
            (\p ->
                case p.paneContent of
                    StaticContent _ ->
                        True

                    SelectableContent _ ->
                        False
            )
        |> Maybe.withDefault False


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


{-| Get the currently selected item from a pane. Handles all index mapping
automatically — filter, tree view, and scroll are all accounted for. Returns
`Nothing` if the selection is on a directory node (in tree view) or if the
index is out of bounds.

    case Layout.selectedItem "files" model.files layout model.layout of
        Just file ->
            showFileDetails file

        Nothing ->
            showDirectoryInfo

-}
selectedItem : String -> List item -> Layout msg -> State -> Maybe item
selectedItem paneId items layout (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId

        idx : Int
        idx =
            Dict.get stateKey s.paneStates
                |> Maybe.map .selectedIndex
                |> Maybe.withDefault 0

        -- Map through filter if active
        filterState : Maybe FilterState
        filterState =
            Dict.get stateKey s.filterStates

        filteredIdx : Int
        filteredIdx =
            mapFilteredIndex idx filterState

        -- Map through tree if active
        treeConfig : Maybe { toPath : Int -> List String }
        treeConfig =
            getTreeConfigForPane paneId layout

        treeState : TreeState
        treeState =
            getTreeStateForPane stateKey (State s)
    in
    case treeConfig of
        Just tc ->
            if treeState.showTree then
                let
                    totalCount : Int
                    totalCount =
                        List.length items

                    rows : List TreeRow
                    rows =
                        buildTreeRows tc.toPath totalCount treeState
                in
                rows
                    |> List.drop idx
                    |> List.head
                    |> Maybe.andThen
                        (\row ->
                            case row.originalIndex of
                                Just origIdx ->
                                    List.drop origIdx items |> List.head

                                Nothing ->
                                    -- Directory node
                                    Nothing
                        )

            else
                List.drop filteredIdx items |> List.head

        Nothing ->
            List.drop filteredIdx items |> List.head


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


{-| Internal: set selected index and auto-scroll to keep it visible.
Uses the context stored in State (set via withContext / GotContext).
The layout state's context already has the bottom-bar-adjusted height,
so we only subtract 2 for pane borders.
-}
setSelectedIndexAndScroll : String -> Int -> Int -> State -> State
setSelectedIndexAndScroll paneId index totalItems (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId

        ps : PaneState
        ps =
            Dict.get stateKey s.paneStates
                |> Maybe.withDefault defaultPaneState

        clampedIndex : Int
        clampedIndex =
            max 0 index

        -- State context already has layout height (terminal - 1 for bottom bar)
        -- Subtract 2 for pane top + bottom borders
        visibleHeight : Int
        visibleHeight =
            s.context.height - 2

        newOffset : Int
        newOffset =
            ensureVisible clampedIndex ps.scrollOffset visibleHeight totalItems 2
    in
    State
        { s
            | paneStates =
                Dict.insert stateKey
                    { ps | selectedIndex = clampedIndex, scrollOffset = newOffset }
                    s.paneStates
        }


{-| Get the total item count for a pane. Useful for displaying "N of M" counters
without manually computing `List.length` on your items list.

    footer =
        String.fromInt (Layout.selectedIndex "list" state + 1)
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


    info =
        Layout.scrollInfo "docs" layout model.layout

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


{-| Set search mode. When `True`, the focused pane's border turns cyan
(like lazygit's visual feedback during search/filter). Call with `False`
to restore normal green border.

    -- When opening search:
    Layout.setSearching True model.layout

    -- When closing search:
    Layout.setSearching False model.layout

-}
setSearching : Bool -> State -> State
setSearching isSearching (State s) =
    State { s | searching = isSearching }


{-| Handle a key event for built-in layout navigation. Routes number keys,
filter (`/`), and search to the appropriate pane.

Returns `( newState, maybeMsg, handled )`:

  - `maybeMsg` is `Just msg` when the filter changes the selected item (fires `onSelect`)
  - `handled` is `True` if the key was consumed by the layout

```
case Layout.handleKeyEvent event layout model.layout of
    ( newLayout, Just msg, True ) ->
        update msg { model | layout = newLayout }

    ( newLayout, Nothing, True ) ->
        ( { model | layout = newLayout }, Effect.none )

    ( _, _, False ) ->
        handleAppKey event model
```

-}
handleKeyEvent : Tui.Sub.KeyEvent -> Layout msg -> State -> ( State, Maybe msg, Bool )
handleKeyEvent event layout (State s) =
    let
        focusedId : Maybe String
        focusedId =
            s.focusedPaneId

        focusedStateKey : Maybe String
        focusedStateKey =
            focusedId
                |> Maybe.map (\pid -> resolveStateKey pid layout)

        activeFilterState : Maybe FilterState
        activeFilterState =
            focusedStateKey
                |> Maybe.andThen (\key -> Dict.get key s.filterStates)

        activeSearchState : Maybe SearchState
        activeSearchState =
            focusedStateKey
                |> Maybe.andThen (\key -> Dict.get key s.searchStates)
    in
    case activeFilterState of
        Just fs ->
            -- A filter is active on the focused pane
            handleFilterKeyEvent event layout fs (State s)

        Nothing ->
            case activeSearchState of
                Just ss ->
                    -- A search is active on the focused pane
                    handleSearchKeyEvent event layout ss (State s)

                Nothing ->
                    -- No filter or search active on the focused pane.
                    -- But if Escape is pressed and ANY pane has an active filter/search,
                    -- clear it (handles the case where user switched panes after filtering).
                    if event.key == Tui.Sub.Escape && (not (Dict.isEmpty s.filterStates) || not (Dict.isEmpty s.searchStates)) then
                        -- Map selections back to original indices for any active filters
                        let
                            restoredPaneStates : Dict String PaneState
                            restoredPaneStates =
                                Dict.foldl
                                    (\key fs pStates ->
                                        case Dict.get key pStates of
                                            Just ps ->
                                                Dict.insert key
                                                    { ps | selectedIndex = mapFilteredIndex ps.selectedIndex (Just fs) }
                                                    pStates

                                            Nothing ->
                                                pStates
                                    )
                                    s.paneStates
                                    s.filterStates
                        in
                        ( State
                            { s
                                | filterStates = Dict.empty
                                , searchStates = Dict.empty
                                , searching = False
                                , paneStates = restoredPaneStates
                            }
                        , Nothing
                        , True
                        )

                    else
                        handleNormalKeyEvent event layout (State s)


handleFilterKeyEvent : Tui.Sub.KeyEvent -> Layout msg -> FilterState -> State -> ( State, Maybe msg, Bool )
handleFilterKeyEvent event layout fs (State s) =
    let
        focusedId : String
        focusedId =
            s.focusedPaneId |> Maybe.withDefault ""

        stateKey : String
        stateKey =
            resolveStateKey focusedId layout
    in
    case fs.mode of
        FilterTyping ->
            case event.key of
                Tui.Sub.Character c ->
                    let
                        newQuery : String
                        newQuery =
                            fs.query ++ String.fromChar c

                        newIndices : List Int
                        newIndices =
                            case getFilterTextForPane focusedId layout of
                                Just getFilterText ->
                                    computeFilteredIndices newQuery getFilterText (getItemCountForPane focusedId layout)

                                Nothing ->
                                    fs.filteredIndices

                        selectMsg : Maybe msg
                        selectMsg =
                            case newIndices of
                                firstOriginalIndex :: _ ->
                                    getOnSelectForPane focusedId layout
                                        |> Maybe.map (\onSelect -> onSelect firstOriginalIndex)

                                [] ->
                                    Nothing
                    in
                    ( State
                        { s
                            | filterStates =
                                Dict.insert stateKey
                                    { query = newQuery
                                    , mode = FilterTyping
                                    , filteredIndices = newIndices
                                    }
                                    s.filterStates
                            , paneStates =
                                Dict.insert stateKey
                                    { selectedIndex = 0, scrollOffset = 0 }
                                    s.paneStates
                        }
                    , selectMsg
                    , True
                    )

                Tui.Sub.Backspace ->
                    let
                        newQuery : String
                        newQuery =
                            String.dropRight 1 fs.query

                        newIndices : List Int
                        newIndices =
                            case getFilterTextForPane focusedId layout of
                                Just getFilterText ->
                                    computeFilteredIndices newQuery getFilterText (getItemCountForPane focusedId layout)

                                Nothing ->
                                    fs.filteredIndices

                        selectMsg : Maybe msg
                        selectMsg =
                            case newIndices of
                                firstOriginalIndex :: _ ->
                                    getOnSelectForPane focusedId layout
                                        |> Maybe.map (\onSelect -> onSelect firstOriginalIndex)

                                [] ->
                                    Nothing
                    in
                    ( State
                        { s
                            | filterStates =
                                Dict.insert stateKey
                                    { query = newQuery
                                    , mode = FilterTyping
                                    , filteredIndices = newIndices
                                    }
                                    s.filterStates
                            , paneStates =
                                Dict.insert stateKey
                                    { selectedIndex = 0, scrollOffset = 0 }
                                    s.paneStates
                        }
                    , selectMsg
                    , True
                    )

                Tui.Sub.Enter ->
                    if String.isEmpty fs.query then
                        -- Empty query: clear filter entirely
                        ( State
                            { s
                                | filterStates = Dict.remove stateKey s.filterStates
                                , searching = False
                            }
                        , Nothing
                        , True
                        )

                    else
                        -- Non-empty query: switch to FilterApplied mode
                        ( State
                            { s
                                | filterStates =
                                    Dict.insert stateKey
                                        { fs | mode = FilterApplied }
                                        s.filterStates
                                , searching = False
                            }
                        , Nothing
                        , True
                        )

                Tui.Sub.Escape ->
                    -- Clear filter, map selection back to original index (lazygit behavior)
                    let
                        ps : PaneState
                        ps =
                            Dict.get stateKey s.paneStates
                                |> Maybe.withDefault defaultPaneState

                        originalIndex : Int
                        originalIndex =
                            mapFilteredIndex ps.selectedIndex (Just fs)
                    in
                    ( State
                        { s
                            | filterStates = Dict.remove stateKey s.filterStates
                            , searching = False
                            , paneStates =
                                Dict.insert stateKey
                                    { ps | selectedIndex = originalIndex }
                                    s.paneStates
                        }
                    , Nothing
                    , True
                    )

                _ ->
                    ( State s, Nothing, True )

        FilterApplied ->
            case event.key of
                Tui.Sub.Escape ->
                    -- Clear filter, map selection back to original index (lazygit behavior)
                    let
                        ps : PaneState
                        ps =
                            Dict.get stateKey s.paneStates
                                |> Maybe.withDefault defaultPaneState

                        originalIndex : Int
                        originalIndex =
                            mapFilteredIndex ps.selectedIndex (Just fs)
                    in
                    ( State
                        { s
                            | filterStates = Dict.remove stateKey s.filterStates
                            , searching = False
                            , paneStates =
                                Dict.insert stateKey
                                    { ps | selectedIndex = originalIndex }
                                    s.paneStates
                        }
                    , Nothing
                    , True
                    )

                Tui.Sub.Character '/' ->
                    -- Re-enter typing mode with current query
                    ( State
                        { s
                            | filterStates =
                                Dict.insert stateKey
                                    { fs | mode = FilterTyping }
                                    s.filterStates
                            , searching = True
                        }
                    , Nothing
                    , True
                    )

                _ ->
                    -- Not consumed — let normal navigation work
                    ( State s, Nothing, False )


handleNormalKeyEvent : Tui.Sub.KeyEvent -> Layout msg -> State -> ( State, Maybe msg, Bool )
handleNormalKeyEvent event layout (State s) =
    let
        -- Try tree key handling first
        treeResult : Maybe ( State, Maybe msg, Bool )
        treeResult =
            case s.focusedPaneId of
                Just focusedId ->
                    case getTreeConfigForPane focusedId layout of
                        Just tc ->
                            let
                                stateKey : String
                                stateKey =
                                    resolveStateKey focusedId layout

                                ts : TreeState
                                ts =
                                    Dict.get stateKey s.treeStates
                                        |> Maybe.withDefault defaultTreeState
                            in
                            handleTreeKeyEvent event tc stateKey ts (State s)

                        Nothing ->
                            Nothing

                Nothing ->
                    Nothing
    in
    case treeResult of
        Just result ->
            result

        Nothing ->
            handleNormalKeyEventFallback event layout (State s)


handleTreeKeyEvent :
    Tui.Sub.KeyEvent
    -> { toPath : Int -> List String }
    -> String
    -> TreeState
    -> State
    -> Maybe ( State, Maybe msg, Bool )
handleTreeKeyEvent event tc stateKey ts (State s) =
    case event.key of
        Tui.Sub.Character c ->
            if c == '`' then
                -- Toggle tree/flat view
                Just
                    ( State
                        { s
                            | treeStates =
                                Dict.insert stateKey
                                    { ts | showTree = not ts.showTree }
                                    s.treeStates
                            , paneStates =
                                Dict.insert stateKey
                                    defaultPaneState
                                    s.paneStates
                        }
                    , Nothing
                    , True
                    )

            else if c == '-' && ts.showTree then
                -- Collapse all directories
                let
                    focusedId : String
                    focusedId =
                        s.focusedPaneId |> Maybe.withDefault ""

                    itemCount_ : Int
                    itemCount_ =
                        case findPane focusedId (Horizontal []) of
                            _ ->
                                -- Need to get item count from tree config
                                -- We can count items by trying indices until toPath returns []
                                countTreeItems tc.toPath 0

                    allDirPaths : Set String
                    allDirPaths =
                        collectAllDirPaths tc.toPath itemCount_
                in
                Just
                    ( State
                        { s
                            | treeStates =
                                Dict.insert stateKey
                                    { ts | collapsedPaths = allDirPaths }
                                    s.treeStates
                            , paneStates =
                                Dict.insert stateKey
                                    defaultPaneState
                                    s.paneStates
                        }
                    , Nothing
                    , True
                    )

            else if c == '=' && ts.showTree then
                -- Expand all directories
                Just
                    ( State
                        { s
                            | treeStates =
                                Dict.insert stateKey
                                    { ts | collapsedPaths = Set.empty }
                                    s.treeStates
                            , paneStates =
                                Dict.insert stateKey
                                    defaultPaneState
                                    s.paneStates
                        }
                    , Nothing
                    , True
                    )

            else
                Nothing

        Tui.Sub.Enter ->
            if ts.showTree then
                -- Check if current row is a directory
                let
                    ps : PaneState
                    ps =
                        Dict.get stateKey s.paneStates
                            |> Maybe.withDefault defaultPaneState

                    focusedId : String
                    focusedId =
                        s.focusedPaneId |> Maybe.withDefault ""

                    itemCount_ : Int
                    itemCount_ =
                        countTreeItems tc.toPath 0

                    treeRows : List TreeRow
                    treeRows =
                        buildTreeRows tc.toPath itemCount_ ts

                    maybeRow : Maybe TreeRow
                    maybeRow =
                        treeRows |> List.drop ps.selectedIndex |> List.head
                in
                case maybeRow of
                    Just treeRow ->
                        if treeRow.isDirectory then
                            -- Toggle collapse
                            let
                                newCollapsed : Set String
                                newCollapsed =
                                    if Set.member treeRow.path ts.collapsedPaths then
                                        Set.remove treeRow.path ts.collapsedPaths

                                    else
                                        Set.insert treeRow.path ts.collapsedPaths
                            in
                            Just
                                ( State
                                    { s
                                        | treeStates =
                                            Dict.insert stateKey
                                                { ts | collapsedPaths = newCollapsed }
                                                s.treeStates
                                    }
                                , Nothing
                                , True
                                )

                        else
                            -- Leaf node: let the app handle it
                            Nothing

                    Nothing ->
                        Nothing

            else
                Nothing

        _ ->
            Nothing


{-| Count items by checking how many valid paths the toPath function returns.
We use a simple approach: try indices starting from 0 until toPath returns [].
-}
countTreeItems : (Int -> List String) -> Int -> Int
countTreeItems toPath idx =
    -- elm-review: known-unoptimized-recursion
    case toPath idx of
        [] ->
            idx

        _ ->
            countTreeItems toPath (idx + 1)


handleNormalKeyEventFallback : Tui.Sub.KeyEvent -> Layout msg -> State -> ( State, Maybe msg, Bool )
handleNormalKeyEventFallback event layout (State s) =
    case event.key of
        Tui.Sub.Character c ->
            if c == '/' then
                -- Check if the focused pane is filterable or searchable
                case s.focusedPaneId of
                    Just focusedId ->
                        if paneIsFilterable focusedId layout then
                            let
                                stateKey : String
                                stateKey =
                                    resolveStateKey focusedId layout

                                totalCount : Int
                                totalCount =
                                    getItemCountForPane focusedId layout
                            in
                            ( State
                                { s
                                    | filterStates =
                                        Dict.insert stateKey
                                            { query = ""
                                            , mode = FilterTyping
                                            , filteredIndices = List.range 0 (totalCount - 1)
                                            }
                                            s.filterStates
                                    , searching = True
                                }
                            , Nothing
                            , True
                            )

                        else if paneIsSearchable focusedId layout then
                            let
                                stateKey : String
                                stateKey =
                                    resolveStateKey focusedId layout
                            in
                            ( State
                                { s
                                    | searchStates =
                                        Dict.insert stateKey
                                            { query = ""
                                            , mode = SearchTyping
                                            , matchPositions = []
                                            , currentMatchIndex = 0
                                            }
                                            s.searchStates
                                    , searching = True
                                }
                            , Nothing
                            , True
                            )

                        else
                            ( State s, Nothing, False )

                    Nothing ->
                        ( State s, Nothing, False )

            else
                -- Number key pane focus
                let
                    panes : List (PaneConfig msg)
                    panes =
                        case layout of
                            Horizontal ps ->
                                ps

                            Vertical ps ->
                                ps

                    paneIndex : Maybe Int
                    paneIndex =
                        case Char.toCode c - Char.toCode '1' of
                            idx ->
                                if idx >= 0 && idx < List.length panes then
                                    Just idx

                                else
                                    Nothing
                in
                case paneIndex of
                    Just idx ->
                        case List.drop idx panes |> List.head of
                            Just paneConfig ->
                                ( State { s | focusedPaneId = Just paneConfig.id }, Nothing, True )

                            Nothing ->
                                ( State s, Nothing, False )

                    Nothing ->
                        ( State s, Nothing, False )

        _ ->
            ( State s, Nothing, False )


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
            (TuiScreen.concat
                [ TuiScreen.text "[1]" |> TuiScreen.bold |> TuiScreen.fg Ansi.Color.cyan
                , TuiScreen.text "Modules" |> TuiScreen.bold
                , TuiScreen.text " [2]" |> TuiScreen.dim
                , TuiScreen.text "Changes" |> TuiScreen.dim
                ]
            )

-}
withTitleScreen : Screen -> Pane msg -> Pane msg
withTitleScreen screen (PaneConstructor config) =
    PaneConstructor { config | titleScreen = Just screen }


{-| Set a styled Screen as the bottom border footer. If both `withFooter`
and `withFooterScreen` are used on the same pane, this one wins.
Renders right-aligned on the bottom border.

    |> Layout.withFooterScreen
        (TuiScreen.concat
            [ TuiScreen.text (String.fromInt idx) |> TuiScreen.bold
            , TuiScreen.text " of " |> TuiScreen.dim
            , TuiScreen.text (String.fromInt total) |> TuiScreen.bold
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
            (TuiScreen.concat
                [ TuiScreen.text "Filter: " |> TuiScreen.dim
                , Input.view { width = 20 } filterState
                ]
            )

The inline footer takes 1 row from the content area. If the pane is too
short for both content and footer, the footer is still shown.

-}
withInlineFooter : Screen -> Pane msg -> Pane msg
withInlineFooter screen (PaneConstructor config) =
    PaneConstructor { config | inlineFooter = Just screen }


{-| Set a scroll callback for a pane. The framework fires this message
with the new scroll position whenever the pane's scroll offset changes
(via keyboard navigation, mouse scroll, or effects).

Use this for scroll-spy: sync another pane's selection to the visible
heading based on scroll position.

    Layout.pane "docs"
        { title = "Documentation", width = Layout.fill }
        (Layout.content cachedLines |> Layout.withSearchable)
        |> Layout.withOnScroll DocsPaneScrolled

-}
withOnScroll : (Int -> msg) -> Pane msg -> Pane msg
withOnScroll callback (PaneConstructor config) =
    PaneConstructor { config | onScroll = Just callback }


{-| Receive a message when the user clicks on a hyperlink within this pane.
The callback receives the URL string from the `TuiScreen.link { url }` that wraps the
clicked text. When a pane has both `withOnLinkClick` and `selectableList`,
link clicks take priority — clicking a hyperlink fires `onLinkClick`, clicking
non-link text fires `onSelect`.

    Layout.pane "docs"
        { title = "Documentation", width = Layout.fill }
        (Layout.content cachedLines |> Layout.withSearchable)
        |> Layout.withOnLinkClick (\url -> NavigateToLink url)

-}
withOnLinkClick : (String -> msg) -> Pane msg -> Pane msg
withOnLinkClick callback (PaneConstructor config) =
    PaneConstructor { config | onLinkClick = Just callback }


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
        StaticContent { lineCount } ->
            lineCount

        SelectableContent config ->
            config.itemCount


{-| Map a filtered index (position in the filtered list) back to the
original item index. When no filter is active, returns the index unchanged.
-}
mapFilteredIndex : Int -> Maybe FilterState -> Int
mapFilteredIndex filteredIdx maybeFs =
    case maybeFs of
        Just fs ->
            fs.filteredIndices
                |> List.drop filteredIdx
                |> List.head
                |> Maybe.withDefault filteredIdx

        Nothing ->
            filteredIdx


{-| Smart-case substring matching (lazygit default): if the query contains
any uppercase characters, the match is case-sensitive; otherwise it is
case-insensitive.
-}



-- Smart-case substring matching with space-separated AND terms.
-- Matches lazygit's default filter behavior:
-- "json dec" matches "Json.Decode" (both terms must match)
-- Smart-case per term: case-insensitive unless term has uppercase


matchesFilter : String -> String -> Bool
matchesFilter query text =
    let
        terms : List String
        terms =
            String.words query
                |> List.filter (not << String.isEmpty)
    in
    if List.isEmpty terms then
        True

    else
        List.all (\term -> termMatches term text) terms


termMatches : String -> String -> Bool
termMatches term text =
    let
        caseSensitive : Bool
        caseSensitive =
            String.any Char.isUpper term

        normalize : String -> String
        normalize =
            if caseSensitive then
                identity

            else
                String.toLower
    in
    String.contains (normalize term) (normalize text)


{-| Compute the list of original indices that match the filter query.
-}
computeFilteredIndices : String -> (Int -> String) -> Int -> List Int
computeFilteredIndices query getFilterText totalCount =
    List.range 0 (totalCount - 1)
        |> List.filter (\i -> matchesFilter query (getFilterText i))


{-| Check if a filter is currently active on a pane (either typing or applied).

    if Layout.isFilterActive "fruits" model.layout then
        -- show filter indicator
        ...

-}
isFilterActive : String -> State -> Bool
isFilterActive paneId (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId
    in
    Dict.member stateKey s.filterStates


{-| Get the filter status bar for a pane, if a filter is active.

Returns `Just (TuiScreen.text "Filter: {query}")` while typing,
`Just (TuiScreen.text "Filter: matches for '{query}' <esc>: Exit filter mode")` after Enter,
or `Nothing` when not filtering.

-}
filterStatusBar : String -> State -> Maybe Screen
filterStatusBar paneId (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId
    in
    Dict.get stateKey s.filterStates
        |> Maybe.map
            (\fs ->
                case fs.mode of
                    FilterTyping ->
                        TuiScreen.text ("Filter: " ++ fs.query)

                    FilterApplied ->
                        TuiScreen.text ("Filter: matches for '" ++ fs.query ++ "' <esc>: Exit filter mode")
            )


{-| Get the filter status bar for whichever pane is currently being filtered.
Checks all panes — use this instead of checking each pane individually.

    case Layout.activeFilterStatusBar model.layout of
        Just filterBar ->
            filterBar

        Nothing ->
            myNormalOptionsBar

-}
activeFilterStatusBar : State -> Maybe Screen
activeFilterStatusBar (State s) =
    let
        filterResult : Maybe Screen
        filterResult =
            s.filterStates
                |> Dict.toList
                |> List.filterMap
                    (\( _, fs ) ->
                        case fs.mode of
                            FilterTyping ->
                                Just (TuiScreen.text ("Filter: " ++ fs.query))

                            FilterApplied ->
                                Just (TuiScreen.text ("Filter: matches for '" ++ fs.query ++ "' <esc>: Exit filter mode"))
                    )
                |> List.head

        searchResult : Maybe Screen
        searchResult =
            s.searchStates
                |> Dict.toList
                |> List.filterMap
                    (\( _, ss ) ->
                        Just (searchStatusBarFromState ss)
                    )
                |> List.head
    in
    case filterResult of
        Just _ ->
            filterResult

        Nothing ->
            searchResult


{-| Check if a pane has filterable content.
-}
paneIsFilterable : String -> Layout msg -> Bool
paneIsFilterable paneId layout =
    findPane paneId layout
        |> Maybe.andThen
            (\p ->
                case p.paneContent of
                    SelectableContent { filterText } ->
                        filterText |> Maybe.map (\_ -> True)

                    StaticContent _ ->
                        Nothing
            )
        |> Maybe.withDefault False


{-| Get the filterText function for a pane, if it exists.
-}
getFilterTextForPane : String -> Layout msg -> Maybe (Int -> String)
getFilterTextForPane paneId layout =
    findPane paneId layout
        |> Maybe.andThen
            (\p ->
                case p.paneContent of
                    SelectableContent { filterText } ->
                        filterText

                    StaticContent _ ->
                        Nothing
            )


{-| Check if a pane has searchable content.
-}
paneIsSearchable : String -> Layout msg -> Bool
paneIsSearchable paneId layout =
    findPane paneId layout
        |> Maybe.andThen
            (\p ->
                case p.paneContent of
                    StaticContent { searchable } ->
                        if searchable then
                            Just True

                        else
                            Nothing

                    SelectableContent _ ->
                        Nothing
            )
        |> Maybe.withDefault False


{-| Get the lines for a searchable pane, if it exists.
-}
getSearchLinesForPane : String -> Layout msg -> Maybe (Array.Array Screen)
getSearchLinesForPane paneId layout =
    findPane paneId layout
        |> Maybe.andThen
            (\p ->
                case p.paneContent of
                    StaticContent { lines, searchable } ->
                        if searchable then
                            Just lines

                        else
                            Nothing

                    SelectableContent _ ->
                        Nothing
            )


{-| Check if a search is currently active on a pane.
-}
isSearchActive : String -> State -> Bool
isSearchActive paneId (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId
    in
    Dict.member stateKey s.searchStates


{-| Get the search status bar for a pane, if a search is active.

Returns `Just` with the search prompt while typing,
match count info after committing, or `Nothing` when not searching.

-}
searchStatusBar : String -> State -> Maybe Screen
searchStatusBar paneId (State s) =
    let
        stateKey : String
        stateKey =
            Dict.get paneId s.activeTabMap
                |> Maybe.withDefault paneId
    in
    Dict.get stateKey s.searchStates
        |> Maybe.map searchStatusBarFromState


searchStatusBarFromState : SearchState -> Screen
searchStatusBarFromState ss =
    case ss.mode of
        SearchTyping ->
            TuiScreen.text ("Search: " ++ ss.query)

        SearchCommitted ->
            if List.isEmpty ss.matchPositions then
                TuiScreen.text ("Search: no matches for '" ++ ss.query ++ "' Esc: exit")

            else
                TuiScreen.text
                    ("Search: matches for '"
                        ++ ss.query
                        ++ "' ("
                        ++ String.fromInt (ss.currentMatchIndex + 1)
                        ++ " of "
                        ++ String.fromInt (List.length ss.matchPositions)
                        ++ ") n: next, N: prev, Esc: exit"
                    )


handleSearchKeyEvent : Tui.Sub.KeyEvent -> Layout msg -> SearchState -> State -> ( State, Maybe msg, Bool )
handleSearchKeyEvent event layout ss (State s) =
    let
        focusedId : String
        focusedId =
            s.focusedPaneId |> Maybe.withDefault ""

        stateKey : String
        stateKey =
            resolveStateKey focusedId layout
    in
    case ss.mode of
        SearchTyping ->
            case event.key of
                Tui.Sub.Character c ->
                    let
                        newQuery : String
                        newQuery =
                            ss.query ++ String.fromChar c
                    in
                    ( State
                        { s
                            | searchStates =
                                Dict.insert stateKey
                                    { ss | query = newQuery }
                                    s.searchStates
                        }
                    , Nothing
                    , True
                    )

                Tui.Sub.Backspace ->
                    let
                        newQuery : String
                        newQuery =
                            String.dropRight 1 ss.query
                    in
                    ( State
                        { s
                            | searchStates =
                                Dict.insert stateKey
                                    { ss | query = newQuery }
                                    s.searchStates
                        }
                    , Nothing
                    , True
                    )

                Tui.Sub.Enter ->
                    if String.isEmpty ss.query then
                        -- Empty query: cancel search
                        ( State
                            { s
                                | searchStates = Dict.remove stateKey s.searchStates
                                , searching = False
                            }
                        , Nothing
                        , True
                        )

                    else
                        -- Compute matches and commit
                        let
                            positions : List { line : Int, col : Int, len : Int }
                            positions =
                                case getSearchLinesForPane focusedId layout of
                                    Just lines ->
                                        computeSearchPositions ss.query lines

                                    Nothing ->
                                        []

                            visibleHeight : Int
                            visibleHeight =
                                s.context.height - 2

                            currentPs : PaneState
                            currentPs =
                                Dict.get stateKey s.paneStates
                                    |> Maybe.withDefault defaultPaneState

                            newOffset : Int
                            newOffset =
                                case List.head positions of
                                    Just firstMatch ->
                                        max 0 (firstMatch.line - visibleHeight // 2)

                                    Nothing ->
                                        currentPs.scrollOffset
                        in
                        ( State
                            { s
                                | searchStates =
                                    Dict.insert stateKey
                                        { query = ss.query
                                        , mode = SearchCommitted
                                        , matchPositions = positions
                                        , currentMatchIndex = 0
                                        }
                                        s.searchStates
                                , searching = False
                                , paneStates =
                                    Dict.insert stateKey
                                        { currentPs | scrollOffset = newOffset }
                                        s.paneStates
                            }
                        , Nothing
                        , True
                        )

                Tui.Sub.Escape ->
                    ( State
                        { s
                            | searchStates = Dict.remove stateKey s.searchStates
                            , searching = False
                        }
                    , Nothing
                    , True
                    )

                _ ->
                    ( State s, Nothing, True )

        SearchCommitted ->
            case event.key of
                Tui.Sub.Character c ->
                    if c == 'n' then
                        -- Next match
                        let
                            totalMatches : Int
                            totalMatches =
                                List.length ss.matchPositions

                            newIndex : Int
                            newIndex =
                                if totalMatches > 0 then
                                    modBy totalMatches (ss.currentMatchIndex + 1)

                                else
                                    0

                            visibleHeight : Int
                            visibleHeight =
                                s.context.height - 2

                            nextPs : PaneState
                            nextPs =
                                Dict.get stateKey s.paneStates
                                    |> Maybe.withDefault defaultPaneState

                            newOffset : Int
                            newOffset =
                                case List.drop newIndex ss.matchPositions |> List.head of
                                    Just match ->
                                        max 0 (match.line - visibleHeight // 2)

                                    Nothing ->
                                        nextPs.scrollOffset
                        in
                        ( State
                            { s
                                | searchStates =
                                    Dict.insert stateKey
                                        { ss | currentMatchIndex = newIndex }
                                        s.searchStates
                                , paneStates =
                                    Dict.insert stateKey
                                        { nextPs | scrollOffset = newOffset }
                                        s.paneStates
                            }
                        , Nothing
                        , True
                        )

                    else if c == 'N' then
                        -- Previous match
                        let
                            totalMatches : Int
                            totalMatches =
                                List.length ss.matchPositions

                            newIndex : Int
                            newIndex =
                                if totalMatches > 0 then
                                    modBy totalMatches (ss.currentMatchIndex - 1 + totalMatches)

                                else
                                    0

                            visibleHeight : Int
                            visibleHeight =
                                s.context.height - 2

                            prevPs : PaneState
                            prevPs =
                                Dict.get stateKey s.paneStates
                                    |> Maybe.withDefault defaultPaneState

                            newOffset : Int
                            newOffset =
                                case List.drop newIndex ss.matchPositions |> List.head of
                                    Just match ->
                                        max 0 (match.line - visibleHeight // 2)

                                    Nothing ->
                                        prevPs.scrollOffset
                        in
                        ( State
                            { s
                                | searchStates =
                                    Dict.insert stateKey
                                        { ss | currentMatchIndex = newIndex }
                                        s.searchStates
                                , paneStates =
                                    Dict.insert stateKey
                                        { prevPs | scrollOffset = newOffset }
                                        s.paneStates
                            }
                        , Nothing
                        , True
                        )

                    else if c == '/' then
                        -- Re-enter typing mode with current query
                        ( State
                            { s
                                | searchStates =
                                    Dict.insert stateKey
                                        { ss | mode = SearchTyping }
                                        s.searchStates
                                , searching = True
                            }
                        , Nothing
                        , True
                        )

                    else
                        -- Not consumed — let normal bindings work
                        ( State s, Nothing, False )

                Tui.Sub.Escape ->
                    -- Clear search
                    ( State
                        { s
                            | searchStates = Dict.remove stateKey s.searchStates
                            , searching = False
                        }
                    , Nothing
                    , True
                    )

                _ ->
                    -- Not consumed
                    ( State s, Nothing, False )


{-| Compute all match positions for a query in a list of lines.
-}
computeSearchPositions : String -> Array.Array Screen -> List { line : Int, col : Int, len : Int }
computeSearchPositions query lines =
    let
        queryLen : Int
        queryLen =
            String.length query

        caseSensitive : Bool
        caseSensitive =
            String.any Char.isUpper query

        normalize : String -> String
        normalize =
            if caseSensitive then
                identity

            else
                String.toLower

        normalizedQuery : String
        normalizedQuery =
            normalize query
    in
    Array.toList lines
        |> List.indexedMap
            (\lineIdx screen ->
                let
                    lineText : String
                    lineText =
                        normalize (TuiScreen.toString screen)
                in
                findAllSubstring normalizedQuery queryLen lineText 0
                    |> List.map (\col -> { line = lineIdx, col = col, len = queryLen })
            )
        |> List.concat


{-| Find all occurrences of a substring in a string, returning start positions.
-}
findAllSubstring : String -> Int -> String -> Int -> List Int
findAllSubstring needle needleLen haystack startFrom =
    -- elm-review: known-unoptimized-recursion
    if startFrom > String.length haystack - needleLen then
        []

    else if String.contains needle (String.dropLeft startFrom haystack |> String.left needleLen) then
        startFrom :: findAllSubstring needle needleLen haystack (startFrom + 1)

    else
        findAllSubstring needle needleLen haystack (startFrom + 1)


{-| Highlight search matches on a single line, preserving existing styles.
-}
highlightMatchesOnLine : Int -> SearchState -> Screen -> Screen
highlightMatchesOnLine lineIdx ss lineScreen =
    let
        matchesOnLine : List { line : Int, col : Int, len : Int }
        matchesOnLine =
            ss.matchPositions
                |> List.filter (\m -> m.line == lineIdx)

        currentMatch : Maybe { line : Int, col : Int, len : Int }
        currentMatch =
            ss.matchPositions
                |> List.drop ss.currentMatchIndex
                |> List.head
    in
    if List.isEmpty matchesOnLine then
        lineScreen

    else
        let
            spans : TuiScreenAdvanced.Line
            spans =
                case TuiScreenAdvanced.toLines lineScreen of
                    first :: _ ->
                        first

                    [] ->
                        []
        in
        buildHighlightedLine spans matchesOnLine currentMatch 0


{-| Build a highlighted line from styled spans and match positions,
preserving existing styles on non-matched segments.
-}
buildHighlightedLine : TuiScreenAdvanced.Line -> List { line : Int, col : Int, len : Int } -> Maybe { line : Int, col : Int, len : Int } -> Int -> Screen
buildHighlightedLine spans matches currentMatch col =
    case matches of
        [] ->
            -- Remaining spans after last match — keep original styles
            TuiScreenAdvanced.fromLine spans

        match :: rest ->
            let
                beforeLen : Int
                beforeLen =
                    match.col - col

                ( beforeSpans, afterBefore ) =
                    splitLineAt beforeLen spans

                ( matchSpans, afterMatch ) =
                    splitLineAt match.len afterBefore

                isCurrent : Bool
                isCurrent =
                    case currentMatch of
                        Just cm ->
                            cm.line == match.line && cm.col == match.col

                        Nothing ->
                            False

                highlightBg : Ansi.Color.Color
                highlightBg =
                    if isCurrent then
                        Ansi.Color.cyan

                    else
                        Ansi.Color.yellow

                highlightedMatchScreen : Screen
                highlightedMatchScreen =
                    matchSpans
                        |> TuiScreenAdvanced.fromLine
                        |> TuiScreen.bg highlightBg
            in
            TuiScreen.concat
                [ TuiScreenAdvanced.fromLine beforeSpans
                , highlightedMatchScreen
                , buildHighlightedLine afterMatch rest currentMatch (match.col + match.len)
                ]


{-| Resolve the hyperlink URL at a given column within a single-line Screen.
Returns `Just url` if the character at `targetCol` has a hyperlink, `Nothing` otherwise.
-}
resolveHyperlinkAt : Int -> Screen -> Maybe String
resolveHyperlinkAt targetCol screen =
    case TuiScreenAdvanced.toLines screen of
        [ spans ] ->
            let
                ( _, right ) =
                    splitLineAt targetCol spans
            in
            case right of
                span :: _ ->
                    TuiScreen.styleHyperlink span.style

                [] ->
                    Nothing

        _ ->
            Nothing


leadingStylingOfLine : Screen -> (Screen -> Screen)
leadingStylingOfLine screen =
    case TuiScreenAdvanced.toLines screen of
        firstLine :: _ ->
            case firstLine of
                firstSpan :: _ ->
                    stylingFromStyle firstSpan.style

                [] ->
                    identity

        [] ->
            identity


stylingFromStyle : TuiScreen.Style -> (Screen -> Screen)
stylingFromStyle style =
    let
        withFg : Screen -> Screen
        withFg =
            case TuiScreen.styleForeground style of
                Just color ->
                    TuiScreen.fg color

                Nothing ->
                    identity

        withBg : Screen -> Screen
        withBg =
            case TuiScreen.styleBackground style of
                Just color ->
                    TuiScreen.bg color

                Nothing ->
                    identity

        withAttrs : Screen -> Screen
        withAttrs =
            TuiScreen.withAttributes (TuiScreen.styleAttributes style)
    in
    withFg >> withBg >> withAttrs


splitLineAt : Int -> TuiScreenAdvanced.Line -> ( TuiScreenAdvanced.Line, TuiScreenAdvanced.Line )
splitLineAt column line =
    if column <= 0 then
        ( [], line )

    else
        splitLineAtHelp column [] line


splitLineAtHelp :
    Int
    -> TuiScreenAdvanced.Line
    -> TuiScreenAdvanced.Line
    -> ( TuiScreenAdvanced.Line, TuiScreenAdvanced.Line )
splitLineAtHelp remaining reversedBefore line =
    if remaining <= 0 then
        ( List.reverse reversedBefore, line )

    else
        case line of
            [] ->
                ( List.reverse reversedBefore, [] )

            span :: rest ->
                let
                    spanLen : Int
                    spanLen =
                        Graphemes.length span.text
                in
                if spanLen <= remaining then
                    splitLineAtHelp (remaining - spanLen) (span :: reversedBefore) rest

                else
                    let
                        splitSpan : TuiScreenAdvanced.Span
                        splitSpan =
                            { span | text = Graphemes.left remaining span.text }
                    in
                    ( List.reverse (splitSpan :: reversedBefore)
                    , { span | text = Graphemes.dropLeft remaining span.text } :: rest
                    )


clampScroll : Int -> Int -> Int -> Int
clampScroll contentLen visibleHeight offset =
    clamp 0 (max 0 (contentLen - visibleHeight)) offset



-- TREE VIEW


type alias TreeRow =
    { originalIndex : Maybe Int
    , label : String
    , depth : Int
    , isDirectory : Bool
    , isExpanded : Bool
    , path : String
    }


{-| Internal tree node used during tree construction.
-}
type TreeNode
    = DirNode String (List TreeNode)
    | LeafNode String Int


defaultTreeState : TreeState
defaultTreeState =
    { showTree = True, collapsedPaths = Set.empty }


getTreeStateForPane : String -> State -> TreeState
getTreeStateForPane paneId (State s) =
    Dict.get paneId s.treeStates
        |> Maybe.withDefault defaultTreeState


getTreeConfigForPane : String -> Layout msg -> Maybe { toPath : Int -> List String }
getTreeConfigForPane paneId layout =
    findPane paneId layout
        |> Maybe.andThen
            (\p ->
                case p.paneContent of
                    SelectableContent { treeConfig } ->
                        treeConfig

                    StaticContent _ ->
                        Nothing
            )


{-| Build visible tree rows from items and tree state.
-}
buildTreeRows : (Int -> List String) -> Int -> TreeState -> List TreeRow
buildTreeRows toPath itemCount_ treeState =
    let
        -- Collect all items with their path segments
        itemsWithPaths : List ( Int, List String )
        itemsWithPaths =
            List.range 0 (itemCount_ - 1)
                |> List.map (\i -> ( i, toPath i ))

        -- Build tree structure
        tree : List TreeNode
        tree =
            buildTree itemsWithPaths

        -- Compress single-child chains
        compressed : List TreeNode
        compressed =
            List.map compressNode tree
    in
    -- Flatten respecting collapsed state
    flattenTree compressed treeState 0 ""


{-| Build a tree structure from items grouped by first path segment.
-}
buildTree : List ( Int, List String ) -> List TreeNode
buildTree itemsWithPaths =
    let
        -- Group items by their first path segment
        grouped : Dict String (List ( Int, List String ))
        grouped =
            List.foldl
                (\( idx, segments ) acc ->
                    case segments of
                        [] ->
                            acc

                        [ single ] ->
                            -- Leaf node: single segment left
                            Dict.update single
                                (\existing ->
                                    case existing of
                                        Nothing ->
                                            Just [ ( idx, [ single ] ) ]

                                        Just items ->
                                            Just (items ++ [ ( idx, [ single ] ) ])
                                )
                                acc

                        first :: rest ->
                            Dict.update first
                                (\existing ->
                                    case existing of
                                        Nothing ->
                                            Just [ ( idx, rest ) ]

                                        Just items ->
                                            Just (items ++ [ ( idx, rest ) ])
                                )
                                acc
                )
                Dict.empty
                itemsWithPaths

        -- Order by first occurrence in original items
        orderedKeys : List String
        orderedKeys =
            List.foldl
                (\( _, segments ) acc ->
                    case segments of
                        [] ->
                            acc

                        first :: _ ->
                            let
                                key =
                                    if List.length segments == 1 then
                                        first

                                    else
                                        first
                            in
                            if List.member key acc then
                                acc

                            else
                                acc ++ [ key ]
                )
                []
                itemsWithPaths
    in
    orderedKeys
        |> List.filterMap
            (\key ->
                Dict.get key grouped
                    |> Maybe.map
                        (\children ->
                            let
                                -- Separate leaf items (single-segment) from subtree items
                                leaves : List ( Int, List String )
                                leaves =
                                    children |> List.filter (\( _, segs ) -> segs == [ key ])

                                subtreeItems : List ( Int, List String )
                                subtreeItems =
                                    children |> List.filter (\( _, segs ) -> segs /= [ key ])
                            in
                            case ( leaves, subtreeItems ) of
                                ( [ ( idx, _ ) ], [] ) ->
                                    -- Single leaf, no subdirectories
                                    LeafNode key idx

                                ( [], _ ) ->
                                    -- Directory with children
                                    DirNode key (buildTree subtreeItems)

                                ( _, [] ) ->
                                    -- Multiple leaves with same name (shouldn't happen in practice)
                                    -- Treat the first one as the leaf
                                    case leaves of
                                        ( idx, _ ) :: _ ->
                                            LeafNode key idx

                                        [] ->
                                            DirNode key []

                                _ ->
                                    -- Mix of leaves and subdirectory items
                                    DirNode key
                                        (List.map (\( idx, _ ) -> LeafNode key idx) leaves
                                            ++ buildTree subtreeItems
                                        )
                        )
            )


{-| Compress single-child directory chains into one node.
e.g. src -> Api -> (children) becomes "src/Api" -> (children)
-}
compressNode : TreeNode -> TreeNode
compressNode node =
    case node of
        LeafNode name idx ->
            LeafNode name idx

        DirNode name children ->
            case children of
                [ DirNode childName grandChildren ] ->
                    -- Single directory child: compress
                    compressNode (DirNode (name ++ "/" ++ childName) grandChildren)

                _ ->
                    DirNode name (List.map compressNode children)


{-| Flatten tree nodes into visible rows respecting collapsed state.
-}
flattenTree : List TreeNode -> TreeState -> Int -> String -> List TreeRow
flattenTree nodes treeState depth parentPath =
    -- elm-review: known-unoptimized-recursion
    List.concatMap
        (\node ->
            case node of
                LeafNode name idx ->
                    [ { originalIndex = Just idx
                      , label = name
                      , depth = depth
                      , isDirectory = False
                      , isExpanded = False
                      , path =
                            if parentPath == "" then
                                name

                            else
                                parentPath ++ "/" ++ name
                      }
                    ]

                DirNode name children ->
                    let
                        dirPath : String
                        dirPath =
                            if parentPath == "" then
                                name

                            else
                                parentPath ++ "/" ++ name

                        isCollapsed : Bool
                        isCollapsed =
                            Set.member dirPath treeState.collapsedPaths

                        dirRow : TreeRow
                        dirRow =
                            { originalIndex = Nothing
                            , label = name
                            , depth = depth
                            , isDirectory = True
                            , isExpanded = not isCollapsed
                            , path = dirPath
                            }
                    in
                    if isCollapsed then
                        [ dirRow ]

                    else
                        dirRow :: flattenTree children treeState (depth + 1) dirPath
        )
        nodes


{-| Collect all directory paths in a tree (for collapse-all).
-}
collectAllDirPaths : (Int -> List String) -> Int -> Set String
collectAllDirPaths toPath itemCount_ =
    let
        itemsWithPaths : List ( Int, List String )
        itemsWithPaths =
            List.range 0 (itemCount_ - 1)
                |> List.map (\i -> ( i, toPath i ))

        tree : List TreeNode
        tree =
            buildTree itemsWithPaths

        compressed : List TreeNode
        compressed =
            List.map compressNode tree
    in
    collectDirPathsFromNodes compressed ""


collectDirPathsFromNodes : List TreeNode -> String -> Set String
collectDirPathsFromNodes nodes parentPath =
    -- elm-review: known-unoptimized-recursion
    List.foldl
        (\node acc ->
            case node of
                LeafNode _ _ ->
                    acc

                DirNode name children ->
                    let
                        dirPath : String
                        dirPath =
                            if parentPath == "" then
                                name

                            else
                                parentPath ++ "/" ++ name
                    in
                    Set.union (Set.insert dirPath acc) (collectDirPathsFromNodes children dirPath)
        )
        Set.empty
        nodes


scrollbarBorder : (Screen -> Screen) -> PaneContent msg -> PaneState -> Maybe FilterState -> Int -> Int -> Screen
scrollbarBorder borderStyling paneContents ps maybeFs contentRow totalHeight =
    let
        contentLen : Int
        contentLen =
            case maybeFs of
                Just fs ->
                    List.length fs.filteredIndices

                Nothing ->
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
            TuiScreen.text "█" |> borderStyling

        else
            TuiScreen.text "│" |> borderStyling

    else
        TuiScreen.text "│" |> borderStyling



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
            , searching : Bool
            , filterStates : Dict String FilterState
            , searchStates : Dict String SearchState
            , treeStates : Dict String TreeState
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
        Tui.Sub.ScrollDown { col, amount } ->
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
                            amount * 2

                        -- Use filtered count when filter is active
                        scrollFilterState : Maybe FilterState
                        scrollFilterState =
                            Dict.get mouseStateKey sWithCtx.filterStates

                        effectiveCount : Int
                        effectiveCount =
                            case scrollFilterState of
                                Just fs ->
                                    List.length fs.filteredIndices

                                Nothing ->
                                    contentLineCount config.paneContent

                        newOffset : Int
                        newOffset =
                            clampScroll effectiveCount (ctx.height - 2) (ps.scrollOffset + delta)
                    in
                    -- Scroll does NOT change focus (lazygit behavior): hovering
                    -- over a pane and scrolling it should not steal focus from
                    -- the currently focused pane.
                    -- Skip state update entirely when scroll is a no-op at the
                    -- boundary to prevent unnecessary re-renders (gocui pattern).
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

        Tui.Sub.ScrollUp { col, amount } ->
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
                            amount * 2

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

        Tui.Sub.Click { row, col } ->
            case findPaneAt col panesWithBounds of
                Just { config, startCol } ->
                    if row == 0 then
                        -- Title bar click — check for tab click
                        case config.tabClickHandler of
                            Just { onTabClick, tabLabels } ->
                                let
                                    -- Column within the pane (after border + jump label)
                                    -- Title starts after: border char + jump label "[N]"
                                    jumpLabelLen : Int
                                    jumpLabelLen =
                                        3

                                    localCol : Int
                                    localCol =
                                        col - startCol - 1 - jumpLabelLen
                                in
                                case findTabAtCol localCol tabLabels of
                                    Just tabId ->
                                        ( State { sWithCtx | focusedPaneId = Just config.id }
                                        , Just (onTabClick tabId)
                                        )

                                    Nothing ->
                                        ( State { sWithCtx | focusedPaneId = Just config.id }, Nothing )

                            Nothing ->
                                ( State { sWithCtx | focusedPaneId = Just config.id }, Nothing )

                    else
                        -- Content area click
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

                            scrolledRow : Int
                            scrolledRow =
                                contentRow + ps.scrollOffset

                            localCol : Int
                            localCol =
                                col - startCol - 1

                            -- Try to resolve a hyperlink at the click position
                            maybeLinkUrl : Maybe String
                            maybeLinkUrl =
                                case config.onLinkClick of
                                    Just _ ->
                                        getContentLine True config ps Nothing Nothing Nothing contentRow
                                            |> resolveHyperlinkAt localCol

                                    Nothing ->
                                        Nothing
                        in
                        case ( maybeLinkUrl, config.onLinkClick ) of
                            ( Just url, Just linkCallback ) ->
                                -- Link click takes priority
                                ( State { sWithCtx | focusedPaneId = Just config.id }
                                , Just (linkCallback url)
                                )

                            _ ->
                                -- Fall through to normal click behavior
                                case config.paneContent of
                                    SelectableContent { onSelect } ->
                                        let
                                            -- Map through filtered indices to get original index
                                            clickFilterState : Maybe FilterState
                                            clickFilterState =
                                                Dict.get clickStateKey sWithCtx.filterStates

                                            originalIndex : Int
                                            originalIndex =
                                                mapFilteredIndex scrolledRow clickFilterState
                                        in
                                        ( State
                                            { sWithCtx
                                                | paneStates =
                                                    Dict.insert clickStateKey
                                                        { ps | selectedIndex = scrolledRow }
                                                        sWithCtx.paneStates
                                                , focusedPaneId = Just config.id
                                            }
                                        , Just (onSelect originalIndex)
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


{-| Find which tab label contains the given column offset within the title bar.
Tab labels are separated by " - " (3 chars).
-}
findTabAtCol : Int -> List { id : String, label : String } -> Maybe String
findTabAtCol col tabLabels =
    findTabAtColHelp col 0 tabLabels


findTabAtColHelp : Int -> Int -> List { id : String, label : String } -> Maybe String
findTabAtColHelp col offset tabs =
    -- elm-review: known-unoptimized-recursion
    case tabs of
        [] ->
            Nothing

        tab :: rest ->
            let
                tabEnd : Int
                tabEnd =
                    offset + String.length tab.label
            in
            if col >= offset && col < tabEnd then
                Just tab.id

            else
                -- Skip past " - " separator (3 chars)
                findTabAtColHelp col (tabEnd + 3) rest



-- RENDERING


{-| Render the layout to a Screen using the given state.
-}
toScreen : State -> Layout msg -> Screen
toScreen state layout =
    TuiScreen.lines (toRows state layout)


{-| Render the layout to a list of row Screens (one per terminal row).

This is useful for compositing modals or overlays on top of the layout —
you can replace specific rows with modal content, then wrap with `TuiScreen.lines`.

-}
toRows : State -> Layout msg -> List Screen
toRows (State s) layout =
    case layout of
        Horizontal panes ->
            toRowsHorizontal s panes

        Vertical panes ->
            toRowsVertical s panes


toRowsHorizontal :
    { a | context : { width : Int, height : Int }, focusedPaneId : Maybe String, maximizedPaneId : Maybe String, paneStates : Dict String PaneState, searching : Bool, filterStates : Dict String FilterState, searchStates : Dict String SearchState, treeStates : Dict String TreeState }
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
            TuiScreen.concat
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

                                borderStyling : Screen -> Screen
                                borderStyling =
                                    if isFocused && s.searching then
                                        TuiScreen.fg Ansi.Color.cyan >> TuiScreen.bold

                                    else if isFocused then
                                        TuiScreen.fg Ansi.Color.green >> TuiScreen.bold

                                    else
                                        TuiScreen.dim
                            in
                            if row == 0 then
                                let
                                    jumpLabel : String
                                    jumpLabel =
                                        "[" ++ String.fromInt (paneIdx + 1) ++ "]"

                                    titleText : String
                                    titleText =
                                        jumpLabel ++ (paneConfig.prefix |> Maybe.withDefault "") ++ paneConfig.title

                                    titleContent : Screen
                                    titleContent =
                                        case paneConfig.titleScreen of
                                            Just screen ->
                                                TuiScreen.concat
                                                    [ TuiScreen.text jumpLabel |> borderStyling
                                                    , TuiScreen.truncateWidth (innerW - 1 - String.length jumpLabel) screen
                                                    ]

                                            Nothing ->
                                                TuiScreen.text titleText |> borderStyling

                                    titleWidth : Int
                                    titleWidth =
                                        case paneConfig.titleScreen of
                                            Just screen ->
                                                String.length jumpLabel + String.length (TuiScreen.toString (TuiScreen.truncateWidth (innerW - 1 - String.length jumpLabel) screen))

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
                                            TuiScreen.empty

                                        else
                                            TuiScreen.text " "
                                in
                                TuiScreen.concat
                                    [ gap
                                    , TuiScreen.text "╭─" |> borderStyling
                                    , titleContent
                                    , TuiScreen.text (String.repeat fillLen "─") |> borderStyling
                                    , TuiScreen.text "╮" |> borderStyling
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
                                                        TuiScreen.text ft |> borderStyling

                                                    Nothing ->
                                                        TuiScreen.empty

                                    footerLen : Int
                                    footerLen =
                                        String.length (TuiScreen.toString footerContent)

                                    dashLen : Int
                                    dashLen =
                                        max 0 (innerW - footerLen)
                                in
                                let
                                    gap : Screen
                                    gap =
                                        if isFirstPane then
                                            TuiScreen.empty

                                        else
                                            TuiScreen.text " "
                                in
                                TuiScreen.concat
                                    [ gap
                                    , TuiScreen.text "╰" |> borderStyling
                                    , TuiScreen.text (String.repeat dashLen "─") |> borderStyling
                                    , if footerLen > 0 then
                                        footerContent

                                      else
                                        TuiScreen.empty
                                    , TuiScreen.text "╯" |> borderStyling
                                    ]

                            else if paneConfig.inlineFooter /= Nothing && row == totalHeight - 2 then
                                -- Inline footer: render widget on the last content row
                                let
                                    footerScreen : Screen
                                    footerScreen =
                                        paneConfig.inlineFooter |> Maybe.withDefault TuiScreen.empty

                                    footerText : String
                                    footerText =
                                        TuiScreen.toString footerScreen

                                    footerWidth : Int
                                    footerWidth =
                                        String.length footerText

                                    padding : Int
                                    padding =
                                        max 0 (innerW - footerWidth)

                                    gap : Screen
                                    gap =
                                        if isFirstPane then
                                            TuiScreen.empty

                                        else
                                            TuiScreen.text " "
                                in
                                TuiScreen.concat
                                    [ gap
                                    , TuiScreen.text "│" |> borderStyling
                                    , TuiScreen.truncateWidth innerW footerScreen
                                    , TuiScreen.text (String.repeat padding " ")
                                    , TuiScreen.text "│" |> borderStyling
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

                                    renderFilterState : Maybe FilterState
                                    renderFilterState =
                                        Dict.get renderStateKey s.filterStates

                                    renderSearchState : Maybe SearchState
                                    renderSearchState =
                                        Dict.get renderStateKey s.searchStates

                                    renderTreeState : Maybe TreeState
                                    renderTreeState =
                                        case paneConfig.paneContent of
                                            SelectableContent { treeConfig } ->
                                                case treeConfig of
                                                    Just _ ->
                                                        Just (Dict.get renderStateKey s.treeStates |> Maybe.withDefault defaultTreeState)

                                                    Nothing ->
                                                        Nothing

                                            StaticContent _ ->
                                                Nothing

                                    contentRow : Int
                                    contentRow =
                                        row - 1

                                    lineScreen : Screen
                                    lineScreen =
                                        getContentLine isFocused paneConfig ps renderFilterState renderSearchState renderTreeState contentRow

                                    lineText : String
                                    lineText =
                                        TuiScreen.toString lineScreen

                                    lineWidth : Int
                                    lineWidth =
                                        String.length lineText

                                    truncatedLine : Screen
                                    truncatedLine =
                                        TuiScreen.truncateWidth innerW lineScreen

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
                                            TuiScreen.text (String.repeat padding " ")
                                                |> leadingStylingOfLine lineScreen

                                        else
                                            TuiScreen.text (String.repeat padding " ")
                                in
                                let
                                    gap : Screen
                                    gap =
                                        if isFirstPane then
                                            TuiScreen.empty

                                        else
                                            TuiScreen.text " "
                                in
                                TuiScreen.concat
                                    [ gap
                                    , TuiScreen.text "│" |> borderStyling
                                    , truncatedLine
                                    , paddingScreen
                                    , scrollbarBorder borderStyling paneConfig.paneContent ps renderFilterState contentRow totalHeight
                                    ]
                        )
                )
    in
    List.range 0 (totalHeight - 1)
        |> List.map renderRow


toRowsVertical :
    { a | context : { width : Int, height : Int }, focusedPaneId : Maybe String, maximizedPaneId : Maybe String, paneStates : Dict String PaneState, searching : Bool, filterStates : Dict String FilterState, searchStates : Dict String SearchState, treeStates : Dict String TreeState }
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

                borderStyling : Screen -> Screen
                borderStyling =
                    if isFocused && s.searching then
                        TuiScreen.fg Ansi.Color.cyan >> TuiScreen.bold

                    else if isFocused then
                        TuiScreen.fg Ansi.Color.green >> TuiScreen.bold

                    else
                        TuiScreen.dim

                vertStateKey : String
                vertStateKey =
                    paneConfig.tabMapping
                        |> Maybe.map .activeTab
                        |> Maybe.withDefault paneConfig.id

                ps : PaneState
                ps =
                    Dict.get vertStateKey s.paneStates
                        |> Maybe.withDefault defaultPaneState

                vertFilterState : Maybe FilterState
                vertFilterState =
                    Dict.get vertStateKey s.filterStates

                vertSearchState : Maybe SearchState
                vertSearchState =
                    Dict.get vertStateKey s.searchStates

                jumpLabel : String
                jumpLabel =
                    "[" ++ String.fromInt (paneIdx + 1) ++ "]"

                titleText : String
                titleText =
                    jumpLabel ++ (paneConfig.prefix |> Maybe.withDefault "") ++ paneConfig.title

                titleContent : Screen
                titleContent =
                    case paneConfig.titleScreen of
                        Just screen ->
                            TuiScreen.concat
                                [ TuiScreen.text jumpLabel |> borderStyling
                                , TuiScreen.truncateWidth (innerW - String.length jumpLabel) screen
                                ]

                        Nothing ->
                            TuiScreen.text titleText |> borderStyling

                titleWidth : Int
                titleWidth =
                    String.length (TuiScreen.toString titleContent)

                fillLen : Int
                fillLen =
                    max 0 (innerW - titleWidth)

                topBorder : Screen
                topBorder =
                    TuiScreen.concat
                        [ TuiScreen.text
                            (if isFirstPane then
                                "╭"

                             else
                                "├"
                            )
                            |> borderStyling
                        , titleContent
                        , TuiScreen.text (String.repeat fillLen "─") |> borderStyling
                        , TuiScreen.text
                            (if isFirstPane then
                                "╮"

                             else
                                "┤"
                            )
                            |> borderStyling
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
                                            TuiScreen.text ft |> borderStyling

                                        Nothing ->
                                            TuiScreen.empty

                        footerLen : Int
                        footerLen =
                            String.length (TuiScreen.toString footerContent)

                        dashLen : Int
                        dashLen =
                            max 0 (innerW - footerLen)
                    in
                    TuiScreen.concat
                        [ TuiScreen.text "╰" |> borderStyling
                        , TuiScreen.text (String.repeat dashLen "─") |> borderStyling
                        , if footerLen > 0 then
                            footerContent

                          else
                            TuiScreen.empty
                        , TuiScreen.text "╯" |> borderStyling
                        ]

                -- Content rows: top border + content, last pane also gets bottom border
                numContentRows : Int
                numContentRows =
                    if isLastPane then
                        paneHeight - 2

                    else
                        paneHeight - 1

                vertTreeState : Maybe TreeState
                vertTreeState =
                    case paneConfig.paneContent of
                        SelectableContent { treeConfig } ->
                            case treeConfig of
                                Just _ ->
                                    Just (Dict.get vertStateKey s.treeStates |> Maybe.withDefault defaultTreeState)

                                Nothing ->
                                    Nothing

                        StaticContent _ ->
                            Nothing

                contentRows : List Screen
                contentRows =
                    List.range 0 (numContentRows - 1)
                        |> List.map
                            (\contentRow ->
                                let
                                    lineScreen : Screen
                                    lineScreen =
                                        getContentLine isFocused paneConfig ps vertFilterState vertSearchState vertTreeState contentRow

                                    lineText : String
                                    lineText =
                                        TuiScreen.toString lineScreen

                                    lineWidth : Int
                                    lineWidth =
                                        String.length lineText

                                    truncatedLine : Screen
                                    truncatedLine =
                                        TuiScreen.truncateWidth innerW lineScreen

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
                                            TuiScreen.text (String.repeat padding " ")
                                                |> leadingStylingOfLine lineScreen

                                        else
                                            TuiScreen.text (String.repeat padding " ")
                                in
                                TuiScreen.concat
                                    [ TuiScreen.text "│" |> borderStyling
                                    , truncatedLine
                                    , paddingScreen
                                    , TuiScreen.text "│" |> borderStyling
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


getContentLine : Bool -> PaneConfig msg -> PaneState -> Maybe FilterState -> Maybe SearchState -> Maybe TreeState -> Int -> Screen
getContentLine isFocused paneConfig ps maybeFilterState maybeSearchState maybeTreeState contentRow =
    let
        scrolledRow : Int
        scrolledRow =
            contentRow + ps.scrollOffset
    in
    case paneConfig.paneContent of
        StaticContent { lines } ->
            let
                baseLine : Screen
                baseLine =
                    Array.get scrolledRow lines
                        |> Maybe.withDefault TuiScreen.empty
            in
            case maybeSearchState of
                Just ss ->
                    case ss.mode of
                        SearchCommitted ->
                            highlightMatchesOnLine scrolledRow ss baseLine

                        SearchTyping ->
                            baseLine

                Nothing ->
                    baseLine

        SelectableContent selConfig ->
            case ( selConfig.treeConfig, maybeTreeState ) of
                ( Just tc, Just ts ) ->
                    if ts.showTree then
                        -- Tree mode: render tree rows
                        let
                            treeRows : List TreeRow
                            treeRows =
                                buildTreeRows tc.toPath selConfig.itemCount ts

                            maybeRow : Maybe TreeRow
                            maybeRow =
                                treeRows |> List.drop scrolledRow |> List.head
                        in
                        case maybeRow of
                            Nothing ->
                                TuiScreen.empty

                            Just treeRow ->
                                renderTreeRow isFocused selConfig treeRow scrolledRow ps.selectedIndex

                    else
                        -- Flat mode: fall through to normal rendering
                        renderSelectableRow isFocused selConfig ps maybeFilterState scrolledRow

                _ ->
                    renderSelectableRow isFocused selConfig ps maybeFilterState scrolledRow


renderTreeRow :
    Bool
    ->
        { a
            | renderItem : Int -> Screen
            , renderSelected : Int -> Screen
            , renderSelectedUnfocused : Int -> Screen
        }
    -> TreeRow
    -> Int
    -> Int
    -> Screen
renderTreeRow isFocused selConfig treeRow scrolledRow selIdx =
    let
        indent : String
        indent =
            String.repeat (treeRow.depth * 2) " "

        isSelected : Bool
        isSelected =
            scrolledRow == selIdx
    in
    if treeRow.isDirectory then
        let
            icon : String
            icon =
                if treeRow.isExpanded then
                    "▼ "

                else
                    "▸ "

            dirLabel : Screen
            dirLabel =
                TuiScreen.text (indent ++ icon ++ treeRow.label) |> TuiScreen.bold
        in
        if isSelected then
            dirLabel |> TuiScreen.bg Ansi.Color.blue

        else
            dirLabel

    else
        case treeRow.originalIndex of
            Just origIdx ->
                let
                    baseScreen : Screen
                    baseScreen =
                        if isSelected then
                            if isFocused then
                                selConfig.renderSelected origIdx

                            else
                                selConfig.renderSelectedUnfocused origIdx

                        else
                            selConfig.renderItem origIdx
                in
                if treeRow.depth > 0 then
                    TuiScreen.concat [ TuiScreen.text indent, baseScreen ]

                else
                    baseScreen

            Nothing ->
                TuiScreen.empty


renderSelectableRow :
    Bool
    ->
        { a
            | renderItem : Int -> Screen
            , renderSelected : Int -> Screen
            , renderSelectedUnfocused : Int -> Screen
        }
    -> PaneState
    -> Maybe FilterState
    -> Int
    -> Screen
renderSelectableRow isFocused selConfig ps maybeFilterState scrolledRow =
    case maybeFilterState of
        Just fs ->
            if scrolledRow >= List.length fs.filteredIndices then
                TuiScreen.empty

            else
                let
                    originalIndex : Int
                    originalIndex =
                        mapFilteredIndex scrolledRow (Just fs)
                in
                if scrolledRow == ps.selectedIndex then
                    if isFocused then
                        selConfig.renderSelected originalIndex

                    else
                        selConfig.renderSelectedUnfocused originalIndex

                else
                    selConfig.renderItem originalIndex

        Nothing ->
            if scrolledRow == ps.selectedIndex then
                if isFocused then
                    selConfig.renderSelected scrolledRow

                else
                    selConfig.renderSelectedUnfocused scrolledRow

            else
                selConfig.renderItem scrolledRow


resolveWidths : Int -> List Width -> List Int
resolveWidths totalWidth widthSpecs =
    let
        fixedTotal : Int
        fixedTotal =
            widthSpecs
                |> List.filterMap
                    (\w ->
                        case w of
                            Fixed n ->
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

                            Fixed _ ->
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
                    Fixed n ->
                        n

                    Fill weight ->
                        if totalWeight > 0 then
                            (remaining * weight) // totalWeight

                        else
                            0
            )



-- RAW EVENT


{-| A raw terminal event that wasn't consumed by the framework's built-in
handling. Use `onRawEvent` in `compileApp` to receive these.

  - `UnhandledKey` — a key press that didn't match any built-in nav key,
    Layout filter/search key, or user binding.
  - `Click` — a mouse click that wasn't consumed by pane selection or tab
    clicks. Useful for clickable content (hyperlinks, buttons).
  - `Scroll` — a mouse scroll event. The framework handles scroll for pane
    content, but passes through any scroll that wasn't consumed.

-}
type RawEvent
    = UnhandledKey Tui.Sub.KeyEvent
    | Click { row : Int, col : Int, button : Tui.Sub.MouseButton }
    | Scroll { row : Int, col : Int, direction : ScrollDirection }


{-| Scroll direction for raw scroll events.
-}
type ScrollDirection
    = ScrollingUp
    | ScrollingDown


{-| Context passed to the `update` function in `compileApp`. Provides
read-only access to framework-managed layout state.

  - `context` — terminal width, height, and color profile
  - `focusedPane` — the ID of the currently focused pane, if any
  - `scrollPosition` — get the scroll offset of a pane by ID
  - `selectedIndex` — get the selected index of a pane by ID

-}
type alias UpdateContext =
    { context : Tui.Context
    , focusedPane : Maybe String
    , scrollPosition : String -> Int
    , selectedIndex : String -> Int
    }



-- COMPILE APP


{-| Opaque wrapper around the user's model. Holds all framework-managed state
(Layout.State, toast queue, spinner tick, modal interaction state, etc.).
-}
type FrameworkModel model msg
    = FrameworkModel
        { userModel : model
        , layoutState : State
        , statusState : Tui.Status.State
        , spinnerTick : Int
        , context : Tui.Context
        , modalState : ModalInteractionState msg
        , previousItemCounts : Dict String Int
        }


{-| Get the currently focused pane ID from a `FrameworkModel`. Useful in tests
with [`TuiTest.ensureModel`](Test-Tui#ensureModel) — see [`Tui.Layout.Test`](Tui-Layout-Test)
for convenient wrappers.
-}
frameworkFocusedPane : FrameworkModel model msg -> Maybe String
frameworkFocusedPane (FrameworkModel fw) =
    focusedPane fw.layoutState


{-| Get the selected index for a pane from a `FrameworkModel`.
-}
frameworkSelectedIndex : String -> FrameworkModel model msg -> Int
frameworkSelectedIndex paneId (FrameworkModel fw) =
    selectedIndex paneId fw.layoutState


{-| Get the scroll position for a pane from a `FrameworkModel`.
-}
frameworkScrollPosition : String -> FrameworkModel model msg -> Int
frameworkScrollPosition paneId (FrameworkModel fw) =
    scrollPosition paneId fw.layoutState


{-| Get the user model from a `FrameworkModel`.
-}
frameworkUserModel : FrameworkModel model msg -> model
frameworkUserModel (FrameworkModel fw) =
    fw.userModel


{-| Opaque message type wrapping user messages and framework-internal events.
-}
type FrameworkMsg msg
    = UserMsg msg
    | KeyPressed Tui.Sub.KeyEvent
    | Mouse Tui.Sub.MouseEvent
    | GotPaste String
    | GotContext { width : Int, height : Int }
    | StatusTick


{-| Internal state for modal interaction (typing, cursor, picker filter, etc.).
-}
type ModalInteractionState msg
    = NoModal
    | PromptInteraction Tui.Prompt.State
    | PickerInteraction PickerInteractionState
    | MenuInteraction (Tui.Menu.State msg)
    | HelpInteraction
        { filterText : String
        , scrollOffset : Int
        }
    | ConfirmInteraction


type alias PickerInteractionState =
    { filterText : String
    , selectedIndex : Int
    , scrollOffset : Int
    , labels : List String
    , filteredIndices : List Int
    }


{-| Transform a declarative TUI app configuration into a
[`Tui.ProgramConfig`](Tui#ProgramConfig).

The user describes WHAT (panes, actions, status, modals) and `compileApp`
handles HOW (rendering, key routing, subscriptions, state management). The
result is a [`Tui.ProgramConfig`](Tui#ProgramConfig); wrap it with
[`Tui.program`](Tui#program) and finalize with
[`Tui.toScript`](Tui#toScript) to produce a runnable `Script`, or pass it
directly to [`Test.Tui.start`](Test-Tui#start) for pure-Elm tests.

    run : Script
    run =
        Tui.program
            (Layout.compileApp
                { data = loadCommits
                , init = init
                , update = update
                , view = view
                , bindings = bindings
                , status = status
                , modal = modal
                , onRawEvent = Nothing
                }
            )
            |> Tui.toScript

The `data` BackendTask runs before `init` while the terminal is still in
normal mode.

-}
compileApp :
    { data : BackendTask FatalError data
    , init : data -> ( model, LayoutEffect.Effect msg )
    , update : UpdateContext -> msg -> model -> ( model, LayoutEffect.Effect msg )
    , view : Tui.Context -> model -> Layout msg
    , bindings : { focusedPane : Maybe String } -> model -> List (Group msg)
    , status : model -> { waiting : Maybe String }
    , modal : model -> Maybe (Modal msg)
    , onRawEvent : Maybe (RawEvent -> msg)
    }
    -> Tui.ProgramConfig data (FrameworkModel model msg) (FrameworkMsg msg)
compileApp config =
    { data = config.data
    , init = compileInit config
    , update = compileUpdate config
    , view = compileView config
    , subscriptions = compileSubscriptions config
    }



-- COMPILED INIT


compileInit :
    { a
        | init : data -> ( model, LayoutEffect.Effect msg )
        , update : UpdateContext -> msg -> model -> ( model, LayoutEffect.Effect msg )
        , view : Tui.Context -> model -> Layout msg
    }
    -> data
    -> ( FrameworkModel model msg, Effect (FrameworkMsg msg) )
compileInit config loadedData =
    let
        ( userModel, userEffect ) =
            config.init loadedData

        defaultContext : Tui.Context
        defaultContext =
            { width = 80, height = 24, colorProfile = Tui.TrueColor }

        layout : Layout msg
        layout =
            config.view defaultContext userModel

        layoutState : State
        layoutState =
            init
                |> withContext { width = defaultContext.width, height = max 1 (defaultContext.height - 1) }
                |> autoFocusFirstPane layout

        itemCounts : Dict String Int
        itemCounts =
            extractItemCounts layout

        -- Fire onSelect for the initially selected item synchronously
        initialSelectMsg : Maybe msg
        initialSelectMsg =
            case focusedPane layoutState of
                Just paneId ->
                    case getOnSelectForPane paneId layout of
                        Just onSelect ->
                            Just (onSelect (selectedIndex paneId layoutState))

                        Nothing ->
                            Nothing

                Nothing ->
                    Nothing

        initUpdateCtx : UpdateContext
        initUpdateCtx =
            { context = defaultContext
            , focusedPane = focusedPane layoutState
            , scrollPosition = \pId -> scrollPosition pId layoutState
            , selectedIndex = \pId -> selectedIndex pId layoutState
            }

        ( finalUserModel, initialSelectEffects ) =
            case initialSelectMsg of
                Just selectMsg ->
                    let
                        ( updatedModel, selectEffect ) =
                            config.update initUpdateCtx selectMsg userModel
                    in
                    ( updatedModel, [ selectEffect ] )

                Nothing ->
                    ( userModel, [] )

        initFw : { layoutState : State, statusState : Tui.Status.State, previousItemCounts : Dict String Int }
        initFw =
            { layoutState = layoutState, statusState = Tui.Status.init, previousItemCounts = itemCounts }

        ( fwAfterInit, initRuntimeEffect ) =
            extractLayoutEffects userEffect initFw

        ( finalFwState, mappedSelectEffects ) =
            List.foldl
                (\eff ( accFw, accMapped ) ->
                    let
                        ( newFw, mapped ) =
                            extractLayoutEffects eff accFw
                    in
                    ( newFw, mapped :: accMapped )
                )
                ( fwAfterInit, [] )
                initialSelectEffects
    in
    ( FrameworkModel
        { userModel = finalUserModel
        , layoutState = finalFwState.layoutState
        , statusState = finalFwState.statusState
        , spinnerTick = 0
        , context = defaultContext
        , modalState = NoModal
        , previousItemCounts = itemCounts
        }
    , Effect.batch
        (initRuntimeEffect :: List.reverse mappedSelectEffects)
    )


runAsEffect : FrameworkMsg msg -> Effect (FrameworkMsg msg)
runAsEffect msg =
    Effect.perform identity (succeedTask msg)


succeedTask : a -> BackendTask.BackendTask FatalError.FatalError a
succeedTask a =
    BackendTask.succeed a


autoFocusFirstPane : Layout msg -> State -> State
autoFocusFirstPane layout state =
    case focusedPane state of
        Just _ ->
            state

        Nothing ->
            case extractPaneIds layout of
                firstId :: _ ->
                    focusPane firstId state

                [] ->
                    state


extractPaneIds : Layout msg -> List String
extractPaneIds layout =
    case layout of
        Horizontal panes ->
            List.map .id panes

        Vertical panes ->
            List.map .id panes


extractItemCounts : Layout msg -> Dict String Int
extractItemCounts layout =
    let
        panes : List (PaneConfig msg)
        panes =
            case layout of
                Horizontal ps ->
                    ps

                Vertical ps ->
                    ps
    in
    panes
        |> List.filterMap
            (\p ->
                case p.paneContent of
                    SelectableContent selectable ->
                        Just ( p.id, selectable.itemCount )

                    StaticContent static ->
                        Just ( p.id, static.lineCount )
            )
        |> Dict.fromList



-- COMPILED UPDATE


compileUpdate :
    { a
        | update : UpdateContext -> msg -> model -> ( model, LayoutEffect.Effect msg )
        , view : Tui.Context -> model -> Layout msg
        , bindings : { focusedPane : Maybe String } -> model -> List (Group msg)
        , status : model -> { waiting : Maybe String }
        , modal : model -> Maybe (Modal msg)
        , onRawEvent : Maybe (RawEvent -> msg)
    }
    -> FrameworkMsg msg
    -> FrameworkModel model msg
    -> ( FrameworkModel model msg, Effect (FrameworkMsg msg) )
compileUpdate config fwMsg (FrameworkModel fw) =
    case fwMsg of
        StatusTick ->
            ( FrameworkModel
                { fw
                    | spinnerTick = fw.spinnerTick + 1
                    , statusState = Tui.Status.tick fw.statusState
                }
            , Effect.none
            )

        GotContext dims ->
            let
                newContext : Tui.Context
                newContext =
                    { width = dims.width
                    , height = dims.height
                    , colorProfile = fw.context.colorProfile
                    }

                -- Layout state gets height - 1 because compileApp reserves
                -- 1 row for the bottom bar. This ensures navigateDown/Up
                -- compute the correct visible height for auto-scroll.
                layoutContext : { width : Int, height : Int }
                layoutContext =
                    { width = dims.width
                    , height = max 1 (dims.height - 1)
                    }
            in
            ( FrameworkModel
                { fw
                    | context = newContext
                    , layoutState = withContext layoutContext fw.layoutState
                }
            , Effect.none
            )

        GotPaste pastedText ->
            case fw.modalState of
                PromptInteraction promptState ->
                    -- Feed each character through Prompt.handleKeyEvent
                    let
                        newPromptState : Tui.Prompt.State
                        newPromptState =
                            String.foldl
                                (\c state ->
                                    let
                                        ( updatedState, _ ) =
                                            Tui.Prompt.handleKeyEvent
                                                { key = Tui.Sub.Character c, modifiers = [] }
                                                state
                                    in
                                    updatedState
                                )
                                promptState
                                pastedText
                    in
                    ( FrameworkModel
                        { fw | modalState = PromptInteraction newPromptState }
                    , Effect.none
                    )

                _ ->
                    ( FrameworkModel fw, Effect.none )

        Mouse mouseEvent ->
            let
                layout : Layout msg
                layout =
                    config.view fw.context fw.userModel

                ( newLayoutState, maybeMsg ) =
                    handleMouse mouseEvent { width = fw.context.width, height = fw.context.height } layout fw.layoutState

                scrollMsgs : List msg
                scrollMsgs =
                    scrollCallbackMsgs fw.layoutState newLayoutState layout

                ( afterClickModel, afterClickEffect ) =
                    case maybeMsg of
                        Just msg ->
                            applyUserMsg config msg (FrameworkModel { fw | layoutState = newLayoutState })

                        Nothing ->
                            -- Pass unhandled mouse events to onRawEvent
                            case config.onRawEvent of
                                Just toMsg ->
                                    let
                                        rawEvent : Maybe RawEvent
                                        rawEvent =
                                            case mouseEvent of
                                                Tui.Sub.Click { row, col, button } ->
                                                    Just (Click { row = row, col = col, button = button })

                                                Tui.Sub.ScrollUp pos ->
                                                    Just (Scroll { row = pos.row, col = pos.col, direction = ScrollingUp })

                                                Tui.Sub.ScrollDown pos ->
                                                    Just (Scroll { row = pos.row, col = pos.col, direction = ScrollingDown })
                                    in
                                    case rawEvent of
                                        Just event ->
                                            applyUserMsg config (toMsg event) (FrameworkModel { fw | layoutState = newLayoutState })

                                        Nothing ->
                                            ( FrameworkModel { fw | layoutState = newLayoutState }, Effect.none )

                                Nothing ->
                                    ( FrameworkModel { fw | layoutState = newLayoutState }, Effect.none )

                -- Apply scroll callback messages synchronously
                ( finalModel, scrollEffects ) =
                    applyScrollMsgs config scrollMsgs afterClickModel
            in
            ( finalModel, Effect.batch (afterClickEffect :: scrollEffects) )

        KeyPressed keyEvent ->
            handleKeyPressed config keyEvent (FrameworkModel fw)

        UserMsg msg ->
            applyUserMsg config msg (FrameworkModel fw)


handleKeyPressed :
    { a
        | update : UpdateContext -> msg -> model -> ( model, LayoutEffect.Effect msg )
        , view : Tui.Context -> model -> Layout msg
        , bindings : { focusedPane : Maybe String } -> model -> List (Group msg)
        , modal : model -> Maybe (Modal msg)
        , onRawEvent : Maybe (RawEvent -> msg)
    }
    -> Tui.Sub.KeyEvent
    -> FrameworkModel model msg
    -> ( FrameworkModel model msg, Effect (FrameworkMsg msg) )
handleKeyPressed config keyEvent (FrameworkModel fw) =
    -- If modal is active, route to modal handler first
    case fw.modalState of
        NoModal ->
            handleKeyPressedNoModal config keyEvent (FrameworkModel fw)

        PromptInteraction promptState ->
            let
                ( newPromptState, result ) =
                    Tui.Prompt.handleKeyEvent keyEvent promptState
            in
            case result of
                Tui.Prompt.Submitted value ->
                    case config.modal fw.userModel of
                        Just (PromptModal modalConfig) ->
                            applyUserMsg config (modalConfig.onSubmit value) (FrameworkModel { fw | modalState = NoModal })

                        _ ->
                            ( FrameworkModel { fw | modalState = NoModal }, Effect.none )

                Tui.Prompt.Cancelled ->
                    case config.modal fw.userModel of
                        Just (PromptModal modalConfig) ->
                            applyUserMsg config modalConfig.onCancel (FrameworkModel { fw | modalState = NoModal })

                        _ ->
                            ( FrameworkModel { fw | modalState = NoModal }, Effect.none )

                Tui.Prompt.Continue ->
                    ( FrameworkModel { fw | modalState = PromptInteraction newPromptState }, Effect.none )

        ConfirmInteraction ->
            case config.modal fw.userModel of
                Just (ConfirmModal modalConfig) ->
                    case keyEvent.key of
                        Tui.Sub.Enter ->
                            applyUserMsg config modalConfig.onConfirm (FrameworkModel { fw | modalState = NoModal })

                        Tui.Sub.Escape ->
                            applyUserMsg config modalConfig.onCancel (FrameworkModel { fw | modalState = NoModal })

                        Tui.Sub.Character 'y' ->
                            applyUserMsg config modalConfig.onConfirm (FrameworkModel { fw | modalState = NoModal })

                        Tui.Sub.Character 'n' ->
                            applyUserMsg config modalConfig.onCancel (FrameworkModel { fw | modalState = NoModal })

                        _ ->
                            ( FrameworkModel fw, Effect.none )

                _ ->
                    ( FrameworkModel fw, Effect.none )

        PickerInteraction picker ->
            handlePickerKey config keyEvent picker (FrameworkModel fw)

        MenuInteraction menuState ->
            let
                ( newMenuState, maybeAction ) =
                    Tui.Menu.handleKeyEvent keyEvent menuState
            in
            case maybeAction of
                Just action ->
                    applyUserMsg config action (FrameworkModel { fw | modalState = NoModal })

                Nothing ->
                    case keyEvent.key of
                        Tui.Sub.Escape ->
                            -- Find the cancel message from the modal config
                            ( FrameworkModel { fw | modalState = NoModal }, Effect.none )

                        _ ->
                            ( FrameworkModel { fw | modalState = MenuInteraction newMenuState }, Effect.none )

        HelpInteraction helpState ->
            case keyEvent.key of
                Tui.Sub.Escape ->
                    -- Fire the user's onClose message to keep their model in sync
                    case config.modal fw.userModel of
                        Just (HelpModal onClose) ->
                            applyUserMsg config onClose (FrameworkModel { fw | modalState = NoModal })

                        _ ->
                            ( FrameworkModel { fw | modalState = NoModal }, Effect.none )

                Tui.Sub.Character 'j' ->
                    let
                        totalRows =
                            helpBodyRowCount helpState.filterText (config.bindings { focusedPane = focusedPane fw.layoutState } fw.userModel)
                    in
                    ( FrameworkModel
                        { fw
                            | modalState =
                                HelpInteraction
                                    { helpState | scrollOffset = min (helpState.scrollOffset + 1) (max 0 (totalRows - 1)) }
                        }
                    , Effect.none
                    )

                Tui.Sub.Arrow Tui.Sub.Down ->
                    let
                        totalRows =
                            helpBodyRowCount helpState.filterText (config.bindings { focusedPane = focusedPane fw.layoutState } fw.userModel)
                    in
                    ( FrameworkModel
                        { fw
                            | modalState =
                                HelpInteraction
                                    { helpState | scrollOffset = min (helpState.scrollOffset + 1) (max 0 (totalRows - 1)) }
                        }
                    , Effect.none
                    )

                Tui.Sub.Character 'k' ->
                    ( FrameworkModel
                        { fw
                            | modalState =
                                HelpInteraction
                                    { helpState | scrollOffset = max 0 (helpState.scrollOffset - 1) }
                        }
                    , Effect.none
                    )

                Tui.Sub.Arrow Tui.Sub.Up ->
                    ( FrameworkModel
                        { fw
                            | modalState =
                                HelpInteraction
                                    { helpState | scrollOffset = max 0 (helpState.scrollOffset - 1) }
                        }
                    , Effect.none
                    )

                _ ->
                    ( FrameworkModel fw, Effect.none )


handlePickerKey :
    { a
        | update : UpdateContext -> msg -> model -> ( model, LayoutEffect.Effect msg )
        , view : Tui.Context -> model -> Layout msg
        , modal : model -> Maybe (Modal msg)
    }
    -> Tui.Sub.KeyEvent
    -> PickerInteractionState
    -> FrameworkModel model msg
    -> ( FrameworkModel model msg, Effect (FrameworkMsg msg) )
handlePickerKey config keyEvent picker (FrameworkModel fw) =
    let
        moveSelection : Int -> PickerInteractionState
        moveSelection delta =
            updatePickerSelection fw.context.height (picker.selectedIndex + delta) picker
    in
    case keyEvent.key of
        Tui.Sub.Escape ->
            case config.modal fw.userModel of
                Just (PickerModal modalConfig) ->
                    applyUserMsg config modalConfig.onCancel (FrameworkModel { fw | modalState = NoModal })

                _ ->
                    ( FrameworkModel { fw | modalState = NoModal }, Effect.none )

        Tui.Sub.Enter ->
            case config.modal fw.userModel of
                Just (PickerModal modalConfig) ->
                    let
                        actualIndex : Int
                        actualIndex =
                            picker.filteredIndices
                                |> List.drop picker.selectedIndex
                                |> List.head
                                |> Maybe.withDefault picker.selectedIndex
                    in
                    applyUserMsg config (modalConfig.onSelectIndex actualIndex) (FrameworkModel { fw | modalState = NoModal })

                _ ->
                    ( FrameworkModel { fw | modalState = NoModal }, Effect.none )

        Tui.Sub.Character 'j' ->
            ( FrameworkModel
                { fw
                    | modalState = PickerInteraction (moveSelection 1)
                }
            , Effect.none
            )

        Tui.Sub.Arrow Tui.Sub.Down ->
            ( FrameworkModel
                { fw
                    | modalState = PickerInteraction (moveSelection 1)
                }
            , Effect.none
            )

        Tui.Sub.Character 'k' ->
            ( FrameworkModel
                { fw
                    | modalState = PickerInteraction (moveSelection -1)
                }
            , Effect.none
            )

        Tui.Sub.Arrow Tui.Sub.Up ->
            ( FrameworkModel
                { fw
                    | modalState = PickerInteraction (moveSelection -1)
                }
            , Effect.none
            )

        Tui.Sub.Backspace ->
            let
                newFilter : String
                newFilter =
                    String.dropRight 1 picker.filterText

                newFiltered : List Int
                newFiltered =
                    filterPickerItems newFilter picker.labels
            in
            ( FrameworkModel
                { fw
                    | modalState =
                        PickerInteraction
                            { picker
                                | filterText = newFilter
                                , filteredIndices = newFiltered
                                , selectedIndex = 0
                                , scrollOffset = 0
                            }
                }
            , Effect.none
            )

        Tui.Sub.Character c ->
            let
                newFilter : String
                newFilter =
                    picker.filterText ++ String.fromChar c

                newFiltered : List Int
                newFiltered =
                    filterPickerItems newFilter picker.labels
            in
            ( FrameworkModel
                { fw
                    | modalState =
                        PickerInteraction
                            { picker
                                | filterText = newFilter
                                , filteredIndices = newFiltered
                                , selectedIndex = 0
                                , scrollOffset = 0
                            }
                }
            , Effect.none
            )

        _ ->
            ( FrameworkModel fw, Effect.none )


filterPickerItems : String -> List String -> List Int
filterPickerItems filter labels =
    if String.isEmpty filter then
        List.indexedMap (\i _ -> i) labels

    else
        let
            lowerFilter : String
            lowerFilter =
                String.toLower filter
        in
        labels
            |> List.indexedMap Tuple.pair
            |> List.filterMap
                (\( i, label ) ->
                    if String.contains lowerFilter (String.toLower label) then
                        Just i

                    else
                        Nothing
                )


updatePickerSelection : Int -> Int -> PickerInteractionState -> PickerInteractionState
updatePickerSelection terminalHeight newIndex picker =
    let
        filteredCount : Int
        filteredCount =
            List.length picker.filteredIndices

        clampedIndex : Int
        clampedIndex =
            if filteredCount <= 0 then
                0

            else
                clamp 0 (filteredCount - 1) newIndex

        visibleLabelRows : Int
        visibleLabelRows =
            pickerVisibleLabelRows terminalHeight

        scrollPadding : Int
        scrollPadding =
            if visibleLabelRows > 2 then
                1

            else
                0

        newScrollOffset : Int
        newScrollOffset =
            if visibleLabelRows <= 0 then
                0

            else
                ensureVisible clampedIndex picker.scrollOffset visibleLabelRows filteredCount scrollPadding
    in
    { picker
        | selectedIndex = clampedIndex
        , scrollOffset = newScrollOffset
    }


pickerVisibleLabelRows : Int -> Int
pickerVisibleLabelRows terminalHeight =
    max 0 (Tui.Modal.maxBodyRows terminalHeight - 1)


handleKeyPressedNoModal :
    { a
        | update : UpdateContext -> msg -> model -> ( model, LayoutEffect.Effect msg )
        , view : Tui.Context -> model -> Layout msg
        , bindings : { focusedPane : Maybe String } -> model -> List (Group msg)
        , modal : model -> Maybe (Modal msg)
        , onRawEvent : Maybe (RawEvent -> msg)
    }
    -> Tui.Sub.KeyEvent
    -> FrameworkModel model msg
    -> ( FrameworkModel model msg, Effect (FrameworkMsg msg) )
handleKeyPressedNoModal config keyEvent (FrameworkModel fw) =
    let
        layout : Layout msg
        layout =
            config.view fw.context fw.userModel
    in
    -- 1. Try built-in nav keys
    case tryBuiltInNav keyEvent layout fw of
        Just ( newFw, maybeMsg ) ->
            let
                scrollMsgs : List msg
                scrollMsgs =
                    scrollCallbackMsgs fw.layoutState newFw.layoutState layout

                ( afterNavModel, afterNavEffect ) =
                    case maybeMsg of
                        Just msg ->
                            applyUserMsg config msg (FrameworkModel newFw)

                        Nothing ->
                            ( FrameworkModel newFw, Effect.none )

                ( finalModel, scrollEffects ) =
                    applyScrollMsgs config scrollMsgs afterNavModel
            in
            ( finalModel, Effect.batch (afterNavEffect :: scrollEffects) )

        Nothing ->
            -- 2. Try Layout.handleKeyEvent (filter/search/tree/numbers)
            let
                ( newLayoutState, maybeLayoutMsg, consumed ) =
                    handleKeyEvent keyEvent layout fw.layoutState

                scrollMsgs2 : List msg
                scrollMsgs2 =
                    scrollCallbackMsgs fw.layoutState newLayoutState layout
            in
            if consumed then
                let
                    ( afterKeyModel, afterKeyEffect ) =
                        case maybeLayoutMsg of
                            Just msg ->
                                applyUserMsg config msg (FrameworkModel { fw | layoutState = newLayoutState })

                            Nothing ->
                                ( FrameworkModel { fw | layoutState = newLayoutState }, Effect.none )

                    ( finalModel2, scrollEffects2 ) =
                        applyScrollMsgs config scrollMsgs2 afterKeyModel
                in
                ( finalModel2, Effect.batch (afterKeyEffect :: scrollEffects2) )

            else
                -- 3. Try user bindings via Keybinding.dispatch
                case Tui.Keybinding.dispatch (config.bindings { focusedPane = focusedPane fw.layoutState } fw.userModel) keyEvent of
                    Just action ->
                        applyUserMsg config action (FrameworkModel { fw | layoutState = newLayoutState })

                    Nothing ->
                        -- 4. Try onRawEvent escape hatch
                        case config.onRawEvent of
                            Just toMsg ->
                                applyUserMsg config (toMsg (UnhandledKey keyEvent)) (FrameworkModel { fw | layoutState = newLayoutState })

                            Nothing ->
                                ( FrameworkModel { fw | layoutState = newLayoutState }, Effect.none )


{-| Try navigate (for selectable panes) or fall back to scroll (for content panes).
-}
navigateOrScroll :
    (String -> Layout msg -> State -> ( State, Maybe msg ))
    -> (String -> Int -> State -> State)
    -> Int
    -> Layout msg
    -> { a | layoutState : State, context : Tui.Context }
    -> Maybe ( { a | layoutState : State, context : Tui.Context }, Maybe msg )
navigateOrScroll navigate scroll delta layout fw =
    case focusedPane fw.layoutState of
        Just paneId ->
            let
                ( newState, maybeMsg ) =
                    navigate paneId layout fw.layoutState
            in
            case maybeMsg of
                Just _ ->
                    Just ( { fw | layoutState = newState }, maybeMsg )

                Nothing ->
                    -- Content pane: fall back to scrolling
                    if isContentPaneId paneId layout then
                        Just ( { fw | layoutState = scroll paneId delta fw.layoutState }, Nothing )

                    else
                        Just ( { fw | layoutState = newState }, Nothing )

        Nothing ->
            Nothing


tryBuiltInNav :
    Tui.Sub.KeyEvent
    -> Layout msg
    ->
        { a
            | layoutState : State
            , context : Tui.Context
        }
    -> Maybe ( { a | layoutState : State, context : Tui.Context }, Maybe msg )
tryBuiltInNav keyEvent layout fw =
    case keyEvent.key of
        Tui.Sub.Character 'j' ->
            navigateOrScroll navigateDown scrollDown 1 layout fw

        Tui.Sub.Arrow Tui.Sub.Down ->
            navigateOrScroll navigateDown scrollDown 1 layout fw

        Tui.Sub.Character 'k' ->
            navigateOrScroll navigateUp scrollUp 1 layout fw

        Tui.Sub.Arrow Tui.Sub.Up ->
            navigateOrScroll navigateUp scrollUp 1 layout fw

        Tui.Sub.Tab ->
            let
                paneIds : List String
                paneIds =
                    extractPaneIds layout

                currentFocused : Maybe String
                currentFocused =
                    focusedPane fw.layoutState

                nextPaneId : Maybe String
                nextPaneId =
                    case currentFocused of
                        Nothing ->
                            List.head paneIds

                        Just current ->
                            paneIds
                                |> List.indexedMap Tuple.pair
                                |> List.filter (\( _, id ) -> id == current)
                                |> List.head
                                |> Maybe.map Tuple.first
                                |> Maybe.map (\i -> modBy (List.length paneIds) (i + 1))
                                |> Maybe.andThen (\i -> paneIds |> List.drop i |> List.head)
            in
            case nextPaneId of
                Just newPaneId ->
                    Just ( { fw | layoutState = focusPane newPaneId fw.layoutState }, Nothing )

                Nothing ->
                    Nothing

        Tui.Sub.PageDown ->
            navigateOrScroll pageDown scrollDown (fw.context.height - 2) layout fw

        Tui.Sub.PageUp ->
            navigateOrScroll pageUp scrollUp (fw.context.height - 2) layout fw

        Tui.Sub.Character '>' ->
            navigateOrScroll pageDown scrollDown (fw.context.height - 2) layout fw

        Tui.Sub.Character '<' ->
            navigateOrScroll pageUp scrollUp (fw.context.height - 2) layout fw

        _ ->
            -- Check for number keys 1-9 (jump to pane)
            case keyEvent.key of
                Tui.Sub.Character c ->
                    let
                        digit : Maybe Int
                        digit =
                            String.fromChar c
                                |> String.toInt
                    in
                    case digit of
                        Just n ->
                            if n >= 1 && n <= 9 then
                                let
                                    paneIds : List String
                                    paneIds =
                                        extractPaneIds layout
                                in
                                paneIds
                                    |> List.drop (n - 1)
                                    |> List.head
                                    |> Maybe.map
                                        (\targetPaneId ->
                                            ( { fw | layoutState = focusPane targetPaneId fw.layoutState }, Nothing )
                                        )

                            else
                                Nothing

                        Nothing ->
                            Nothing

                _ ->
                    Nothing


{-| Built-in help section for display only (never dispatched against).
Uses `List Screen` directly instead of `Group msg` to avoid needing a `msg`.
-}
helpBodyRowCount : String -> List (Group msg) -> Int
helpBodyRowCount filterText userBindings =
    List.length builtInHelpRows
        + 1
        + List.length (Tui.Keybinding.helpRows filterText userBindings)
        + 1
        + List.length navigationHelpRows


builtInHelpRows : List Screen
builtInHelpRows =
    [ Tui.Keybinding.sectionHeader "Navigation"
    , Tui.Keybinding.infoRow "j/↓" "Navigate down"
    , Tui.Keybinding.infoRow "k/↑" "Navigate up"
    , Tui.Keybinding.infoRow "tab" "Switch pane"
    , Tui.Keybinding.infoRow "/" "Filter/Search"
    , Tui.Keybinding.infoRow "n/N" "Next/prev match"
    , Tui.Keybinding.infoRow "esc" "Exit mode"
    , Tui.Keybinding.infoRow ">/pgdn" "Page down"
    , Tui.Keybinding.infoRow "</pgup" "Page up"
    ]


applyScrollMsgs :
    { a
        | update : UpdateContext -> msg -> model -> ( model, LayoutEffect.Effect msg )
        , view : Tui.Context -> model -> Layout msg
        , modal : model -> Maybe (Modal msg)
    }
    -> List msg
    -> FrameworkModel model msg
    -> ( FrameworkModel model msg, List (Effect (FrameworkMsg msg)) )
applyScrollMsgs config msgs model =
    List.foldl
        (\msg ( accModel, accEffects ) ->
            let
                ( newModel, eff ) =
                    applyUserMsg config msg accModel
            in
            ( newModel, eff :: accEffects )
        )
        ( model, [] )
        msgs


applyUserMsg :
    { a
        | update : UpdateContext -> msg -> model -> ( model, LayoutEffect.Effect msg )
        , view : Tui.Context -> model -> Layout msg
        , modal : model -> Maybe (Modal msg)
    }
    -> msg
    -> FrameworkModel model msg
    -> ( FrameworkModel model msg, Effect (FrameworkMsg msg) )
applyUserMsg config msg (FrameworkModel fw) =
    let
        updateCtx : UpdateContext
        updateCtx =
            { context = fw.context
            , focusedPane = focusedPane fw.layoutState
            , scrollPosition = \paneId -> scrollPosition paneId fw.layoutState
            , selectedIndex = \paneId -> selectedIndex paneId fw.layoutState
            }

        ( newUserModel, userEffect ) =
            config.update updateCtx msg fw.userModel

        -- Process layout effects from the user's effect
        ( frameworkState, remainingEffect ) =
            extractLayoutEffects userEffect fw

        -- Check if modal kind changed
        newModalState : ModalInteractionState msg
        newModalState =
            syncModalState config fw.modalState fw.userModel newUserModel

        -- Check for auto-reset: if item counts changed, reset selection
        newLayout : Layout msg
        newLayout =
            config.view fw.context newUserModel

        newItemCounts : Dict String Int
        newItemCounts =
            extractItemCounts newLayout

        ( stateAfterReset, autoSelectMsgs ) =
            handleAutoReset fw.previousItemCounts newItemCounts newLayout frameworkState.layoutState

        -- Apply auto-select messages synchronously (no effect round-trip)
        autoResetCtx : UpdateContext
        autoResetCtx =
            { context = fw.context
            , focusedPane = focusedPane stateAfterReset
            , scrollPosition = \pId -> scrollPosition pId stateAfterReset
            , selectedIndex = \pId -> selectedIndex pId stateAfterReset
            }

        ( finalUserModel, autoSelectEffects ) =
            List.foldl
                (\selectMsg ( accModel, accEffects ) ->
                    let
                        ( updatedModel, eff ) =
                            config.update autoResetCtx selectMsg accModel
                    in
                    ( updatedModel, eff :: accEffects )
                )
                ( newUserModel, [] )
                autoSelectMsgs

        ( autoFwState, mappedAutoEffects ) =
            List.foldl
                (\eff ( accFw, accMapped ) ->
                    let
                        ( newFw, mapped ) =
                            extractLayoutEffects eff accFw
                    in
                    ( newFw, mapped :: accMapped )
                )
                ( { frameworkState | layoutState = stateAfterReset }, [] )
                (List.reverse autoSelectEffects)
    in
    ( FrameworkModel
        { autoFwState
            | userModel = finalUserModel
            , modalState = newModalState
            , previousItemCounts = newItemCounts
        }
    , Effect.batch
        (remainingEffect :: List.reverse mappedAutoEffects)
    )


extractLayoutEffects :
    LayoutEffect.Effect msg
    ->
        { a
            | layoutState : State
            , statusState : Tui.Status.State
            , previousItemCounts : Dict String Int
        }
    ->
        ( { a
            | layoutState : State
            , statusState : Tui.Status.State
            , previousItemCounts : Dict String Int
          }
        , Effect (FrameworkMsg msg)
        )
extractLayoutEffects effect fw =
    -- elm-review: known-unoptimized-recursion
    case effect of
        LayoutEffect.Runtime inner ->
            ( fw, Effect.map UserMsg inner )

        LayoutEffect.Batch effects ->
            let
                ( finalFw, collectedEffects ) =
                    List.foldl
                        (\nextEffect ( accFw, accEffects ) ->
                            let
                                ( newFw, mappedEffect ) =
                                    extractLayoutEffects nextEffect accFw
                            in
                            ( newFw, mappedEffect :: accEffects )
                        )
                        ( fw, [] )
                        effects
            in
            ( finalFw, Effect.batch (List.reverse collectedEffects) )

        LayoutEffect.Toast message ->
            ( { fw | statusState = Tui.Status.toast message fw.statusState }, Effect.none )

        LayoutEffect.ErrorToast message ->
            ( { fw | statusState = Tui.Status.errorToast message fw.statusState }, Effect.none )

        LayoutEffect.ResetScroll paneId ->
            ( { fw | layoutState = resetScroll paneId fw.layoutState }, Effect.none )

        LayoutEffect.ScrollTo paneId offset ->
            ( { fw
                | layoutState =
                    fw.layoutState
                        |> resetScroll paneId
                        |> scrollDown paneId offset
              }
            , Effect.none
            )

        LayoutEffect.ScrollDown paneId amount ->
            ( { fw | layoutState = scrollDown paneId amount fw.layoutState }, Effect.none )

        LayoutEffect.ScrollUp paneId amount ->
            ( { fw | layoutState = scrollUp paneId amount fw.layoutState }, Effect.none )

        LayoutEffect.SetSelectedIndex paneId index ->
            let
                totalItems : Int
                totalItems =
                    Dict.get paneId fw.previousItemCounts |> Maybe.withDefault (index + 1)
            in
            ( { fw | layoutState = setSelectedIndexAndScroll paneId index totalItems fw.layoutState }, Effect.none )

        LayoutEffect.SelectFirst paneId ->
            let
                totalItems : Int
                totalItems =
                    Dict.get paneId fw.previousItemCounts |> Maybe.withDefault 1
            in
            ( { fw | layoutState = setSelectedIndexAndScroll paneId 0 totalItems fw.layoutState }, Effect.none )

        LayoutEffect.FocusPane paneId ->
            ( { fw | layoutState = focusPane paneId fw.layoutState }, Effect.none )


syncModalState :
    { a | modal : model -> Maybe (Modal msg) }
    -> ModalInteractionState msg
    -> model
    -> model
    -> ModalInteractionState msg
syncModalState config previousModalState _ newModel =
    case config.modal newModel of
        Nothing ->
            NoModal

        Just (PromptModal modalConfig) ->
            case previousModalState of
                PromptInteraction _ ->
                    -- Same kind: preserve interaction state
                    previousModalState

                _ ->
                    -- New modal: initialize
                    PromptInteraction
                        (Tui.Prompt.open
                            { title = modalConfig.title
                            , placeholder = ""
                            }
                        )

        Just (ConfirmModal _) ->
            case previousModalState of
                ConfirmInteraction ->
                    previousModalState

                _ ->
                    ConfirmInteraction

        Just (PickerModal modalConfig) ->
            case previousModalState of
                PickerInteraction _ ->
                    previousModalState

                _ ->
                    let
                        allIndices : List Int
                        allIndices =
                            List.indexedMap (\i _ -> i) modalConfig.labels
                    in
                    PickerInteraction
                        { filterText = ""
                        , selectedIndex = 0
                        , scrollOffset = 0
                        , labels = modalConfig.labels
                        , filteredIndices = allIndices
                        }

        Just (MenuModal sections) ->
            case previousModalState of
                MenuInteraction _ ->
                    previousModalState

                _ ->
                    MenuInteraction (Tui.Menu.open sections)

        Just (HelpModal _) ->
            case previousModalState of
                HelpInteraction _ ->
                    previousModalState

                _ ->
                    HelpInteraction { filterText = "", scrollOffset = 0 }


handleAutoReset : Dict String Int -> Dict String Int -> Layout msg -> State -> ( State, List msg )
handleAutoReset previousCounts newCounts layout layoutState =
    let
        changedPanes : List String
        changedPanes =
            Dict.toList newCounts
                |> List.filterMap
                    (\( paneId, newCount ) ->
                        case Dict.get paneId previousCounts of
                            Just oldCount ->
                                if oldCount /= newCount then
                                    Just paneId

                                else
                                    Nothing

                            Nothing ->
                                -- New pane
                                Just paneId
                    )
    in
    List.foldl
        (\paneId ( accState, accMsgs ) ->
            let
                stateWithReset : State
                stateWithReset =
                    setSelectedIndex paneId 0 accState
            in
            case getOnSelectForPane paneId layout of
                Just onSelect ->
                    ( stateWithReset, accMsgs ++ [ onSelect 0 ] )

                Nothing ->
                    ( stateWithReset, accMsgs )
        )
        ( layoutState, [] )
        changedPanes


scrollCallbackMsgs : State -> State -> Layout msg -> List msg
scrollCallbackMsgs oldState newState layout =
    let
        paneConfigs : List (PaneConfig msg)
        paneConfigs =
            case layout of
                Horizontal ps ->
                    ps

                Vertical ps ->
                    ps
    in
    paneConfigs
        |> List.filterMap
            (\p ->
                case p.onScroll of
                    Just callback ->
                        let
                            oldPos : Int
                            oldPos =
                                scrollPosition p.id oldState

                            newPos : Int
                            newPos =
                                scrollPosition p.id newState
                        in
                        if oldPos /= newPos then
                            Just (callback newPos)

                        else
                            Nothing

                    Nothing ->
                        Nothing
            )



-- COMPILED VIEW


compileView :
    { a
        | view : Tui.Context -> model -> Layout msg
        , bindings : { focusedPane : Maybe String } -> model -> List (Group msg)
        , status : model -> { waiting : Maybe String }
        , modal : model -> Maybe (Modal msg)
    }
    -> Tui.Context
    -> FrameworkModel model msg
    -> Screen
compileView config ctx (FrameworkModel fw) =
    let
        -- Reserve 1 row for the bottom bar (status/filter/options).
        -- Pass the reduced height to the user's view so panes know their
        -- actual available space and footers don't get clipped.
        layoutHeight : Int
        layoutHeight =
            max 1 (ctx.height - 1)

        layoutContext : Tui.Context
        layoutContext =
            { width = ctx.width
            , height = layoutHeight
            , colorProfile = ctx.colorProfile
            }

        -- Full context for modal overlays and bottom bar positioning
        context : Tui.Context
        context =
            ctx

        layout : Layout msg
        layout =
            config.view layoutContext fw.userModel

        layoutState : State
        layoutState =
            withContext layoutContext fw.layoutState

        -- Render panes
        layoutRows : List Screen
        layoutRows =
            toRows layoutState layout

        -- Compose bottom bar
        filterBar : Maybe Screen
        filterBar =
            activeFilterStatusBar layoutState

        statusView : Screen
        statusView =
            Tui.Status.view
                { waiting = (config.status fw.userModel).waiting
                , tick = fw.spinnerTick
                }
                fw.statusState

        optionsBar : Screen
        optionsBar =
            Tui.OptionsBar.view context.width (config.bindings { focusedPane = focusedPane fw.layoutState } fw.userModel)

        -- Priority: filter prompt > waiting spinner > toast > options bar
        bottomBar : Screen
        bottomBar =
            case filterBar of
                Just fb ->
                    fb

                Nothing ->
                    if statusView /= TuiScreen.empty then
                        statusView

                    else
                        optionsBar

        -- Combine layout rows with bottom bar
        allRows : List Screen
        allRows =
            if context.height <= 1 then
                [ bottomBar ]

            else
                let
                    availableForLayout : Int
                    availableForLayout =
                        context.height - 1

                    trimmedRows : List Screen
                    trimmedRows =
                        List.take availableForLayout layoutRows

                    paddedRows : List Screen
                    paddedRows =
                        if List.length trimmedRows < availableForLayout then
                            trimmedRows ++ List.repeat (availableForLayout - List.length trimmedRows) TuiScreen.empty

                        else
                            trimmedRows
                in
                paddedRows ++ [ bottomBar ]

        -- Modal overlay (if any)
        finalRows : List Screen
        finalRows =
            case fw.modalState of
                NoModal ->
                    allRows

                PromptInteraction promptState ->
                    Tui.Modal.overlay
                        { title = Tui.Prompt.title promptState
                        , body = Tui.Prompt.viewBody { width = Tui.Modal.defaultWidth context.width - 2 } promptState
                        , footer = "Enter: confirm │ Esc: cancel"
                        , width = Tui.Modal.defaultWidth context.width
                        }
                        { width = context.width, height = context.height }
                        allRows

                ConfirmInteraction ->
                    case config.modal fw.userModel of
                        Just (ConfirmModal modalConfig) ->
                            Tui.Modal.overlay
                                { title = modalConfig.title
                                , body = [ TuiScreen.text modalConfig.message ]
                                , footer = "y/Enter: confirm │ n/Esc: cancel"
                                , width = Tui.Modal.defaultWidth context.width
                                }
                                { width = context.width, height = context.height }
                                allRows

                        _ ->
                            allRows

                PickerInteraction picker ->
                    case config.modal fw.userModel of
                        Just (PickerModal modalConfig) ->
                            let
                                allLabelRows : List Screen
                                allLabelRows =
                                    picker.filteredIndices
                                        |> List.indexedMap
                                            (\displayIdx originalIdx ->
                                                let
                                                    label : String
                                                    label =
                                                        picker.labels
                                                            |> List.drop originalIdx
                                                            |> List.head
                                                            |> Maybe.withDefault ""
                                                in
                                                if displayIdx == picker.selectedIndex then
                                                    TuiScreen.text ("▸ " ++ label) |> TuiScreen.bg Ansi.Color.blue

                                                else
                                                    TuiScreen.text ("  " ++ label)
                                            )

                                visibleLabelRows : Int
                                visibleLabelRows =
                                    pickerVisibleLabelRows context.height

                                hasOverflow : Bool
                                hasOverflow =
                                    List.length allLabelRows > visibleLabelRows

                                windowedLabelRows : List Screen
                                windowedLabelRows =
                                    if visibleLabelRows <= 0 then
                                        []

                                    else
                                        allLabelRows
                                            |> List.drop picker.scrollOffset
                                            |> List.take visibleLabelRows

                                paddedLabelRows : List Screen
                                paddedLabelRows =
                                    if hasOverflow && List.length windowedLabelRows < visibleLabelRows then
                                        windowedLabelRows
                                            ++ List.repeat (visibleLabelRows - List.length windowedLabelRows) TuiScreen.empty

                                    else
                                        windowedLabelRows

                                filterLine : Screen
                                filterLine =
                                    if String.isEmpty picker.filterText then
                                        TuiScreen.text "Type to filter..." |> TuiScreen.dim

                                    else
                                        TuiScreen.concat
                                            [ TuiScreen.text "/ " |> TuiScreen.fg Ansi.Color.cyan
                                            , TuiScreen.text picker.filterText
                                            ]
                            in
                            Tui.Modal.overlay
                                { title = modalConfig.title
                                , body = filterLine :: paddedLabelRows
                                , footer = "Enter: select │ Esc: cancel"
                                , width = Tui.Modal.defaultWidth context.width
                                }
                                { width = context.width, height = context.height }
                                allRows

                        _ ->
                            allRows

                MenuInteraction menuState ->
                    Tui.Modal.overlay
                        { title = Tui.Menu.title
                        , body = Tui.Menu.viewBodyWithMaxRows (Tui.Modal.maxBodyRows context.height) menuState
                        , footer = "Enter: select │ Esc: cancel"
                        , width = Tui.Modal.defaultWidth context.width
                        }
                        { width = context.width, height = context.height }
                        allRows

                HelpInteraction helpState ->
                    let
                        allHelpRows : List Screen
                        allHelpRows =
                            builtInHelpRows
                                ++ [ TuiScreen.text "" ]
                                ++ Tui.Keybinding.helpRows
                                    helpState.filterText
                                    (config.bindings { focusedPane = focusedPane fw.layoutState } fw.userModel)
                                ++ [ TuiScreen.text "" ]
                                ++ navigationHelpRows

                        totalRows : Int
                        totalRows =
                            List.length allHelpRows

                        -- The modal body should maintain a fixed size equal to the
                        -- full content height (clamped by Modal.overlay to 75%).
                        -- Drop rows for scrolling, then pad back to maintain height.
                        droppedBody : List Screen
                        droppedBody =
                            List.drop helpState.scrollOffset allHelpRows

                        paddedBody : List Screen
                        paddedBody =
                            let
                                dropped =
                                    totalRows - List.length droppedBody
                            in
                            if dropped > 0 then
                                droppedBody ++ List.repeat dropped TuiScreen.empty

                            else
                                droppedBody
                    in
                    Tui.Modal.overlay
                        { title = "Keybindings"
                        , body = paddedBody
                        , footer = "j/k: scroll │ Esc: close"
                        , width = Tui.Modal.defaultWidth context.width
                        }
                        { width = context.width, height = context.height }
                        allRows
    in
    TuiScreen.lines finalRows



-- COMPILED SUBSCRIPTIONS


compileSubscriptions :
    { a | status : model -> { waiting : Maybe String } }
    -> FrameworkModel model msg
    -> Tui.Sub.Sub (FrameworkMsg msg)
compileSubscriptions config (FrameworkModel fw) =
    let
        hasStatusActivity : Bool
        hasStatusActivity =
            Tui.Status.hasActivity
                { waiting = (config.status fw.userModel).waiting }
                fw.statusState

        tickSub : Tui.Sub.Sub (FrameworkMsg msg)
        tickSub =
            if hasStatusActivity then
                Tui.Sub.everyMillis 100 (\_ -> StatusTick)

            else
                Tui.Sub.none
    in
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse Mouse
        , Tui.Sub.onPaste GotPaste
        , Tui.Sub.onResize GotContext
        , tickSub
        ]


{-| Auto-generated help rows for Layout's built-in mouse interactions.
Include these in your help screen so users know about scroll and click.

    helpBody =
        Keybinding.helpRows filterText myBindings
            ++ [ TuiScreen.text "" ]
            ++ Layout.navigationHelpRows

-}
navigationHelpRows : List Screen
navigationHelpRows =
    [ Tui.Keybinding.sectionHeader "Navigation"
    , Tui.Keybinding.infoRow "scroll ↑" "Scroll up"
    , Tui.Keybinding.infoRow "scroll ↓" "Scroll down"
    , Tui.Keybinding.infoRow "click" "Select item"
    ]
