module Tui.Menu exposing
    ( State, open
    , Section, section
    , Item, item, disabledItem
    , handleKeyEvent
    , viewBody, title
    )

{-| Menu with sections, direct key dispatch, and disabled items.

Unlike [`Tui.Picker`](Tui-Picker) which is a searchable fuzzy-filtered list,
a Menu dispatches actions directly by key press — pressing `c` immediately
fires the item bound to `c`. Supports sections with headers, disabled items
with explanatory reasons, and j/k navigation with Enter to confirm.

Render with [`Tui.Modal.overlay`](Tui-Modal#overlay):

    case model.menu of
        Just menuState ->
            Modal.overlay
                { title = Menu.title
                , body = Menu.viewBody menuState
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
                    if event.key == Tui.Escape then
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

@docs viewBody, title

-}

import Ansi.Color
import Tui exposing (plain)


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
    { key : Tui.Key
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
            [ Menu.item { key = Tui.Character 's', label = "Stage", action = "stage" }
            , Menu.disabledItem { key = Tui.Character 'u', label = "Unstage", reason = "Nothing staged" }
            ]
        , Menu.section "Commit"
            [ Menu.item { key = Tui.Character 'c', label = "Commit", action = "commit" }
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

    Menu.item { key = Tui.Character 'c', label = "Commit", action = DoCommit }

-}
item : { key : Tui.Key, label : String, action : msg } -> Item msg
item config =
    Item
        { key = config.key
        , label = config.label
        , result = Enabled config.action
        }


{-| Create a disabled menu item. Shows the reason why it's unavailable.

    Menu.disabledItem { key = Tui.Character 'u', label = "Unstage", reason = "Nothing staged" }

-}
disabledItem : { key : Tui.Key, label : String, reason : String } -> Item msg
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
handleKeyEvent : Tui.KeyEvent -> State msg -> ( State msg, Maybe msg )
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
        Tui.Character 'j' ->
            ( State { s | highlightIndex = min (enabledCount - 1) (s.highlightIndex + 1) }
            , Nothing
            )

        Tui.Character 'k' ->
            ( State { s | highlightIndex = max 0 (s.highlightIndex - 1) }
            , Nothing
            )

        Tui.Arrow Tui.Down ->
            ( State { s | highlightIndex = min (enabledCount - 1) (s.highlightIndex + 1) }
            , Nothing
            )

        Tui.Arrow Tui.Up ->
            ( State { s | highlightIndex = max 0 (s.highlightIndex - 1) }
            , Nothing
            )

        Tui.Enter ->
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
viewBody : State msg -> List Tui.Screen
viewBody (State s) =
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

        highlightedFlatIndex : Maybe Int
        highlightedFlatIndex =
            enabledItems
                |> List.drop s.highlightIndex
                |> List.head
                |> Maybe.map Tuple.first
    in
    s.sections
        |> List.concatMap
            (\sectionData ->
                let
                    header =
                        Tui.text ("--- " ++ sectionData.name ++ " ---")
                            |> Tui.bold

                    rows =
                        sectionData.items
                            |> List.map
                                (\i ->
                                    let
                                        flatIdx =
                                            allItems
                                                |> List.indexedMap Tuple.pair
                                                |> List.filter (\( _, ai ) -> ai == i)
                                                |> List.head
                                                |> Maybe.map Tuple.first

                                        isHighlighted =
                                            flatIdx == highlightedFlatIndex

                                        keyLabel =
                                            keyToString i.key
                                    in
                                    case i.result of
                                        Enabled _ ->
                                            let
                                                row =
                                                    Tui.concat
                                                        [ Tui.text ("  " ++ keyLabel)
                                                            |> Tui.fg Ansi.Color.cyan
                                                            |> Tui.bold
                                                        , Tui.text (" " ++ i.label)
                                                        ]
                                            in
                                            if isHighlighted then
                                                row |> Tui.bg Ansi.Color.blue

                                            else
                                                row

                                        Disabled reason ->
                                            Tui.concat
                                                [ Tui.text ("  " ++ keyLabel)
                                                    |> Tui.dim
                                                , Tui.text (" " ++ i.label)
                                                    |> Tui.dim
                                                , Tui.text (" (" ++ reason ++ ")")
                                                    |> Tui.dim
                                                ]
                                )
                in
                header :: rows
            )


{-| The menu title. Use with [`Tui.Modal.overlay`](Tui-Modal#overlay).
-}
title : String
title =
    "Menu"



-- HELPERS


keyToString : Tui.Key -> String
keyToString key =
    case key of
        Tui.Character c ->
            String.fromChar c

        Tui.Enter ->
            "Enter"

        Tui.Escape ->
            "Esc"

        Tui.Tab ->
            "Tab"

        Tui.Backspace ->
            "Bksp"

        Tui.Delete ->
            "Del"

        Tui.Arrow Tui.Up ->
            "↑"

        Tui.Arrow Tui.Down ->
            "↓"

        Tui.Arrow Tui.Left ->
            "←"

        Tui.Arrow Tui.Right ->
            "→"

        Tui.Home ->
            "Home"

        Tui.End ->
            "End"

        Tui.PageUp ->
            "PgUp"

        Tui.PageDown ->
            "PgDn"

        Tui.FunctionKey n ->
            "F" ++ String.fromInt n
