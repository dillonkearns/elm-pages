module Tui.Menu exposing
    ( State, open
    , Section, section
    , Item, item, disabledItem
    , handleKeyEvent
    , viewBody, viewBodyWithMaxRows, title
    )

{-| Menu with sections, direct key dispatch, and disabled items.

Unlike [`Tui.Picker`](Tui-Picker) which is a searchable fuzzy-filtered list,
a Menu dispatches actions directly by key press — pressing `c` immediately
fires the item bound to `c`. Supports sections with headers, disabled items
with explanatory reasons, and j/k navigation with Enter to confirm.

When using [`Layout.compileApp`](Tui-Layout#compileApp), prefer
[`Layout.menuModal`](Tui-Layout#menuModal) which handles key routing for you.

Render with [`Tui.Modal.overlay`](Tui-Modal#overlay):

    case model.menu of
        Just menuState ->
            Modal.overlay
                { title = Menu.title
                , body = Menu.viewBodyWithMaxRows (Modal.maxBodyRows ctx.height) menuState
                , footer = "Esc: close"
                , width = Modal.defaultWidth ctx.width
                }
                { width = ctx.width, height = ctx.height }
                bgRows

        Nothing ->
            bgRows

Handle keys while the menu is open:

    case model.menu of
        Just menuState ->
            case Menu.handleKeyEvent event menuState of
                ( _, Just action ) ->
                    handleAction action { model | menu = Nothing }

                ( newMenu, Nothing ) ->
                    if event.key == Tui.Event.Escape then
                        ( { model | menu = Nothing }, Effect.none )
                    else
                        ( { model | menu = Just newMenu }, Effect.none )

        Nothing ->
            ...


## Opening a Menu

@docs State, open


## Defining Menu Content

@docs Section, section

@docs Item, item, disabledItem


## Interaction

@docs handleKeyEvent


## Rendering

@docs viewBody, viewBodyWithMaxRows, title

-}

import Ansi.Color
import Tui
import Tui.Event
import Tui.Screen


{-| Opaque menu state. Tracks the items and the current highlight position.
-}
type State msg
    = State
        { sections : List (SectionData msg)
        , highlightIndex : Int -- index into the flattened enabled items
        }


type alias SectionData msg =
    { name : String
    , items : List (ItemData msg)
    }


type alias ItemData msg =
    { key : Tui.Event.Key
    , label : String
    , result : ItemResult msg
    }


type ItemResult msg
    = Enabled msg
    | Disabled String


{-| A menu section (opaque). Create with [`section`](#section).
-}
type Section msg
    = Section (SectionData msg)


{-| A menu item (opaque). Create with [`item`](#item) or [`disabledItem`](#disabledItem).
-}
type Item msg
    = Item (ItemData msg)


{-| Open a menu with the given sections.

    Menu.open
        [ Menu.section "Files"
            [ Menu.item { key = Tui.Event.Character 's', label = "Stage", action = "stage" }
            , Menu.disabledItem { key = Tui.Event.Character 'u', label = "Unstage", reason = "Nothing staged" }
            ]
        , Menu.section "Commit"
            [ Menu.item { key = Tui.Event.Character 'c', label = "Commit", action = "commit" }
            ]
        ]

-}
open : List (Section msg) -> State msg
open sections =
    State
        { sections = List.map (\(Section s) -> s) sections
        , highlightIndex = 0
        }


{-| Create a section with a header and items.
-}
section : String -> List (Item msg) -> Section msg
section name items =
    Section
        { name = name
        , items = List.map (\(Item i) -> i) items
        }


{-| Create an enabled menu item with a key shortcut.

    Menu.item { key = Tui.Event.Character 'c', label = "Commit", action = DoCommit }

-}
item : { key : Tui.Event.Key, label : String, action : msg } -> Item msg
item config =
    Item
        { key = config.key
        , label = config.label
        , result = Enabled config.action
        }


{-| Create a disabled menu item. Shows the reason why it's unavailable.

    Menu.disabledItem { key = Tui.Event.Character 'u', label = "Unstage", reason = "Nothing staged" }

-}
disabledItem : { key : Tui.Event.Key, label : String, reason : String } -> Item msg
disabledItem config =
    Item
        { key = config.key
        , label = config.label
        , result = Disabled config.reason
        }


{-| Handle a key event. Returns the updated state and `Just action` if an
item was activated (by direct key press or Enter on highlighted item).

Direct key dispatch: pressing `c` immediately fires the `c`-bound item.
j/k navigate the highlight, Enter confirms the highlighted item.
Disabled items cannot be activated.

-}
handleKeyEvent : Tui.Event.KeyEvent -> State msg -> ( State msg, Maybe msg )
handleKeyEvent event (State s) =
    let
        allItems : List (ItemData msg)
        allItems =
            s.sections |> List.concatMap .items

        enabledItems : List ( Int, ItemData msg )
        enabledItems =
            allItems
                |> List.indexedMap Tuple.pair
                |> List.filter
                    (\( _, i ) ->
                        case i.result of
                            Enabled _ ->
                                True

                            Disabled _ ->
                                False
                    )

        enabledCount : Int
        enabledCount =
            List.length enabledItems
    in
    case event.key of
        Tui.Event.Character 'j' ->
            ( State { s | highlightIndex = min (enabledCount - 1) (s.highlightIndex + 1) }
            , Nothing
            )

        Tui.Event.Character 'k' ->
            ( State { s | highlightIndex = max 0 (s.highlightIndex - 1) }
            , Nothing
            )

        Tui.Event.Arrow Tui.Event.Down ->
            ( State { s | highlightIndex = min (enabledCount - 1) (s.highlightIndex + 1) }
            , Nothing
            )

        Tui.Event.Arrow Tui.Event.Up ->
            ( State { s | highlightIndex = max 0 (s.highlightIndex - 1) }
            , Nothing
            )

        Tui.Event.Enter ->
            let
                selectedAction =
                    enabledItems
                        |> List.drop s.highlightIndex
                        |> List.head
                        |> Maybe.andThen
                            (\( _, i ) ->
                                case i.result of
                                    Enabled action ->
                                        Just action

                                    Disabled _ ->
                                        Nothing
                            )
            in
            ( State s, selectedAction )

        _ ->
            -- Direct key dispatch: find an enabled item bound to this key
            let
                directMatch =
                    allItems
                        |> List.filterMap
                            (\i ->
                                if i.key == event.key then
                                    case i.result of
                                        Enabled action ->
                                            Just action

                                        Disabled _ ->
                                            Nothing

                                else
                                    Nothing
                            )
                        |> List.head
            in
            ( State s, directMatch )


{-| Render the menu body as a list of Screens (one per row). Use with
[`Tui.Modal.overlay`](Tui-Modal#overlay).

Section headers are styled bold. Items show the key shortcut left-aligned
and the label right of it. The highlighted item has a blue background.
Disabled items are dimmed with the reason shown.

-}
viewBody : State msg -> List Tui.Screen.Screen
viewBody state =
    renderBodyRows state
        |> List.map .screen


{-| Render the menu body clamped to a maximum number of rows, keeping the
highlighted action visible.

This is the preferred rendering helper for long menus in modals:

    Modal.overlay
        { title = Menu.title
        , body = Menu.viewBodyWithMaxRows (Modal.maxBodyRows ctx.height) menuState
        , footer = "Esc: close"
        , width = Modal.defaultWidth ctx.width
        }
        { width = ctx.width, height = ctx.height }
        bgRows

If the menu is shorter than `maxRows`, all rows are returned unchanged. If it
overflows, the returned list is padded so the modal height stays stable near the
end of the list.

-}
viewBodyWithMaxRows : Int -> State msg -> List Tui.Screen.Screen
viewBodyWithMaxRows maxRows state =
    let
        renderedRows : List RenderedRow
        renderedRows =
            renderBodyRows state

        allRows : List Tui.Screen.Screen
        allRows =
            renderedRows
                |> List.map .screen

        visibleRows : Int
        visibleRows =
            max 0 maxRows

        highlightedRowIndex : Maybe Int
        highlightedRowIndex =
            renderedRows
                |> List.indexedMap Tuple.pair
                |> List.filterMap
                    (\( index, row ) ->
                        if row.isHighlighted then
                            Just index

                        else
                            Nothing
                    )
                |> List.head

        scrollPadding : Int
        scrollPadding =
            if visibleRows > 2 then
                1

            else
                0

        scrollOffset : Int
        scrollOffset =
            case highlightedRowIndex of
                Just rowIndex ->
                    scrollOffsetForRow rowIndex visibleRows (List.length allRows) scrollPadding

                Nothing ->
                    0

        windowedRows : List Tui.Screen.Screen
        windowedRows =
            if visibleRows <= 0 then
                []

            else
                allRows
                    |> List.drop scrollOffset
                    |> List.take visibleRows
    in
    if visibleRows <= 0 then
        []

    else if List.length allRows <= visibleRows then
        allRows

    else if List.length windowedRows < visibleRows then
        windowedRows
            ++ List.repeat (visibleRows - List.length windowedRows) Tui.Screen.empty

    else
        windowedRows


type alias RenderedRow =
    { screen : Tui.Screen.Screen
    , isHighlighted : Bool
    }


renderBodyRows : State msg -> List RenderedRow
renderBodyRows (State s) =
    let
        indexedSections : List { name : String, items : List ( Int, ItemData msg ) }
        indexedSections =
            indexSectionItems 0 s.sections

        enabledItems : List ( Int, ItemData msg )
        enabledItems =
            indexedSections
                |> List.concatMap .items
                |> List.filterMap
                    (\( flatIndex, itemData ) ->
                        case itemData.result of
                            Enabled _ ->
                                Just ( flatIndex, itemData )

                            Disabled _ ->
                                Nothing
                    )

        highlightedFlatIndex : Maybe Int
        highlightedFlatIndex =
            enabledItems
                |> List.drop s.highlightIndex
                |> List.head
                |> Maybe.map Tuple.first
    in
    indexedSections
        |> List.concatMap
            (\indexedSection ->
                let
                    header =
                        { screen = Tui.Screen.text ("--- " ++ indexedSection.name ++ " ---") |> Tui.Screen.bold
                        , isHighlighted = False
                        }

                    rows =
                        indexedSection.items
                            |> List.map
                                (\( flatIdx, i ) ->
                                    let
                                        isHighlighted =
                                            Just flatIdx == highlightedFlatIndex

                                        keyLabel =
                                            keyToString i.key

                                        screen =
                                            case i.result of
                                                Enabled _ ->
                                                    let
                                                        row =
                                                            Tui.Screen.concat
                                                                [ Tui.Screen.text ("  " ++ keyLabel)
                                                                    |> Tui.Screen.fg Ansi.Color.cyan
                                                                    |> Tui.Screen.bold
                                                                , Tui.Screen.text (" " ++ i.label)
                                                                ]
                                                    in
                                                    if isHighlighted then
                                                        row |> Tui.Screen.bg Ansi.Color.blue

                                                    else
                                                        row

                                                Disabled reason ->
                                                    Tui.Screen.concat
                                                        [ Tui.Screen.text ("  " ++ keyLabel)
                                                            |> Tui.Screen.dim
                                                        , Tui.Screen.text (" " ++ i.label)
                                                            |> Tui.Screen.dim
                                                        , Tui.Screen.text (" (" ++ reason ++ ")")
                                                            |> Tui.Screen.dim
                                                        ]
                                    in
                                    { screen = screen, isHighlighted = isHighlighted }
                                )
                in
                header :: rows
            )


indexSectionItems : Int -> List (SectionData msg) -> List { name : String, items : List ( Int, ItemData msg ) }
indexSectionItems startIndex sections =
    case sections of
        [] ->
            []

        sectionData :: remainingSections ->
            let
                indexedItems : List ( Int, ItemData msg )
                indexedItems =
                    sectionData.items
                        |> List.indexedMap (\offset itemData -> ( startIndex + offset, itemData ))
            in
            { name = sectionData.name, items = indexedItems }
                :: indexSectionItems (startIndex + List.length sectionData.items) remainingSections


scrollOffsetForRow : Int -> Int -> Int -> Int -> Int
scrollOffsetForRow highlightedRow visibleRows totalRows padding =
    let
        maxOffset : Int
        maxOffset =
            max 0 (totalRows - visibleRows)
    in
    if visibleRows <= 0 then
        0

    else if highlightedRow < padding then
        0

    else if highlightedRow > visibleRows - 1 - padding then
        clamp 0 maxOffset (highlightedRow - visibleRows + 1 + padding)

    else
        0


{-| The menu title. Use with [`Tui.Modal.overlay`](Tui-Modal#overlay).
-}
title : String
title =
    "Menu"



-- HELPERS


keyToString : Tui.Event.Key -> String
keyToString key =
    case key of
        Tui.Event.Character c ->
            String.fromChar c

        Tui.Event.Enter ->
            "Enter"

        Tui.Event.Escape ->
            "Esc"

        Tui.Event.Tab ->
            "Tab"

        Tui.Event.Backspace ->
            "Bksp"

        Tui.Event.Delete ->
            "Del"

        Tui.Event.Arrow Tui.Event.Up ->
            "↑"

        Tui.Event.Arrow Tui.Event.Down ->
            "↓"

        Tui.Event.Arrow Tui.Event.Left ->
            "←"

        Tui.Event.Arrow Tui.Event.Right ->
            "→"

        Tui.Event.Home ->
            "Home"

        Tui.Event.End ->
            "End"

        Tui.Event.PageUp ->
            "PgUp"

        Tui.Event.PageDown ->
            "PgDn"

        Tui.Event.FunctionKey n ->
            "F" ++ String.fromInt n
