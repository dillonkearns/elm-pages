module Tui.Keybinding exposing
    ( Binding, binding, withAlternate, withModifiers
    , Group, group
    , dispatch
    , formatKey, formatBinding
    , helpRows, helpRowsWithSelection, helpRowCount
    , infoRow, sectionHeader
    )

{-| Declarative keybinding system with scoped dispatch and auto-generated help.

Bindings are data (not just pattern matches), grouped into named scopes,
dispatched in priority order, and rendered as a searchable help screen.
The same binding declarations drive [`Tui.OptionsBar`](Tui-OptionsBar) hints,
[`Tui.CommandPalette`](Tui-CommandPalette) search, and help screen generation.

When using [`Layout.compileApp`](Tui-Layout#compileApp), use the simpler
[`Layout.group`](Tui-Layout#group) / [`Layout.binding`](Tui-Layout#binding) wrappers
instead of importing this module directly.

    -- Declare bindings
    globalBindings =
        Keybinding.group "Global"
            [ Keybinding.binding (Tui.Event.Character 'q') "Quit" Quit
            , Keybinding.binding (Tui.Event.Character '?') "Help" ToggleHelp
            ]

    commitBindings =
        Keybinding.group "Commits"
            [ Keybinding.binding (Tui.Event.Character 'j') "Next commit" (Navigate 1)
                |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)
            ]

    -- Dispatch: try focused-pane bindings first, fall through to global
    case Keybinding.dispatch [ commitBindings, globalBindings ] event of
        Just action -> handleAction action model
        Nothing -> ( model, Effect.none )

    -- Help screen: auto-generated, with filtering
    helpBody = Keybinding.helpRows filterText [ commitBindings, globalBindings ]

@docs Binding, binding, withAlternate, withModifiers
@docs Group, group
@docs dispatch
@docs formatKey, formatBinding
@docs helpRows, helpRowsWithSelection, helpRowCount
@docs infoRow, sectionHeader

-}

import Ansi.Color
import Tui
import Tui.Event
import Tui.Screen exposing (plain)


{-| A keybinding: one or more key combinations mapped to an action.
-}
type alias Binding msg =
    { keys : List { key : Tui.Event.Key, modifiers : List Tui.Event.Modifier }
    , description : String
    , action : msg
    }


{-| A named group of bindings (e.g., "Global", "Commits", "Navigation").
Groups are tried in order by `dispatch` — first match wins.
-}
type alias Group msg =
    { name : String
    , bindings : List (Binding msg)
    }


{-| Create a binding with a single key, no modifiers.

    Keybinding.binding (Tui.Event.Character 'q') "Quit" Quit

-}
binding : Tui.Event.Key -> String -> msg -> Binding msg
binding key desc action =
    { keys = [ { key = key, modifiers = [] } ]
    , description = desc
    , action = action
    }


{-| Add an alternate key to a binding. The help screen shows both keys
separated by `/` (e.g., `j/↓`).

    Keybinding.binding (Tui.Event.Character 'j') "Next" NavigateDown
        |> Keybinding.withAlternate (Tui.Event.Arrow Tui.Event.Down)

-}
withAlternate : Tui.Event.Key -> Binding msg -> Binding msg
withAlternate key b =
    { b | keys = b.keys ++ [ { key = key, modifiers = [] } ] }


{-| Create a binding with modifier keys.

    Keybinding.withModifiers [ Tui.Event.Ctrl ] (Tui.Event.Character 's') "Save" Save

-}
withModifiers : List Tui.Event.Modifier -> Tui.Event.Key -> String -> msg -> Binding msg
withModifiers mods key desc action =
    { keys = [ { key = key, modifiers = mods } ]
    , description = desc
    , action = action
    }


{-| Create a named group of bindings.

    Keybinding.group "Commits" [ ... ]

-}
group : String -> List (Binding msg) -> Group msg
group name bindings =
    { name = name, bindings = bindings }



-- DISPATCH


{-| Dispatch a key event against binding groups. Groups are tried in order;
the first matching binding's action is returned. Returns `Nothing` if no
binding matches.

    -- Focused pane bindings take priority over global
    Keybinding.dispatch [ paneBindings, globalBindings ] event

-}
dispatch : List (Group msg) -> Tui.Event.KeyEvent -> Maybe msg
dispatch groups event =
    groups
        |> List.concatMap .bindings
        |> findMatch event


findMatch : Tui.Event.KeyEvent -> List (Binding msg) -> Maybe msg
findMatch event bindings =
    -- elm-review: known-unoptimized-recursion
    case bindings of
        [] ->
            Nothing

        b :: rest ->
            if List.any (\k -> k.key == event.key && matchModifiers k.modifiers event.modifiers) b.keys then
                Just b.action

            else
                findMatch event rest


matchModifiers : List Tui.Event.Modifier -> List Tui.Event.Modifier -> Bool
matchModifiers expected actual =
    List.sort (List.map modifierOrder expected)
        == List.sort (List.map modifierOrder actual)


modifierOrder : Tui.Event.Modifier -> Int
modifierOrder mod =
    case mod of
        Tui.Event.Ctrl ->
            0

        Tui.Event.Alt ->
            1

        Tui.Event.Shift ->
            2



-- KEY FORMATTING


{-| Format a key and modifiers as a human-readable label.

    formatKey (Tui.Event.Character 'j') [] == "j"
    formatKey (Tui.Event.Arrow Tui.Event.Up) [] == "↑"
    formatKey (Tui.Event.Character 'a') [ Tui.Event.Ctrl ] == "ctrl+a"

-}
formatKey : Tui.Event.Key -> List Tui.Event.Modifier -> String
formatKey key modifiers =
    let
        modPrefix : String
        modPrefix =
            modifiers
                |> List.map
                    (\m ->
                        case m of
                            Tui.Event.Ctrl ->
                                "ctrl+"

                            Tui.Event.Alt ->
                                "alt+"

                            Tui.Event.Shift ->
                                "shift+"
                    )
                |> String.concat

        keyStr : String
        keyStr =
            case key of
                Tui.Event.Character ' ' ->
                    "space"

                Tui.Event.Character c ->
                    String.fromChar c

                Tui.Event.Enter ->
                    "enter"

                Tui.Event.Escape ->
                    "esc"

                Tui.Event.Tab ->
                    "tab"

                Tui.Event.Backspace ->
                    "backspace"

                Tui.Event.Delete ->
                    "delete"

                Tui.Event.Arrow Tui.Event.Up ->
                    "↑"

                Tui.Event.Arrow Tui.Event.Down ->
                    "↓"

                Tui.Event.Arrow Tui.Event.Left ->
                    "←"

                Tui.Event.Arrow Tui.Event.Right ->
                    "→"

                Tui.Event.Home ->
                    "home"

                Tui.Event.End ->
                    "end"

                Tui.Event.PageUp ->
                    "pgup"

                Tui.Event.PageDown ->
                    "pgdn"

                Tui.Event.FunctionKey n ->
                    "F" ++ String.fromInt n
    in
    modPrefix ++ keyStr


{-| Format all keys of a binding as a label, separated by `/`.

    formatBinding myBinding == "j/↓"

-}
formatBinding : Binding msg -> String
formatBinding b =
    b.keys
        |> List.map (\k -> formatKey k.key k.modifiers)
        |> String.join "/"



-- HELP SCREEN


{-| Generate help screen rows from binding groups, with optional filtering.

Pass an empty string for no filter. Prefix with `@` to filter by key name
instead of description (lazygit convention).

When filtering is active, section headers are hidden (matching items from
different groups are mixed, so headers would be misleading).

    -- No filter: shows all bindings with section headers
    Keybinding.helpRows "" [ commitBindings, globalBindings ]

    -- Filter by description
    Keybinding.helpRows "quit" [ commitBindings, globalBindings ]

    -- Filter by key name
    Keybinding.helpRows "@ctrl" [ commitBindings, globalBindings ]

Returns `List Screen` suitable for use as a `Tui.Modal.overlay` body.

-}
helpRows : String -> List (Group msg) -> List Tui.Screen.Screen
helpRows filter groups =
    helpRowsWithSelection -1 filter groups


{-| Count the number of selectable binding rows (excluding headers/separators).
Useful for clamping a selected index.
-}
helpRowCount : String -> List (Group msg) -> Int
helpRowCount filter groups =
    filteredBindings filter groups
        |> List.concatMap .bindings
        |> List.length


filteredBindings : String -> List (Group msg) -> List (Group msg)
filteredBindings filter groups =
    let
        isFiltering : Bool
        isFiltering =
            not (String.isEmpty filter)

        matchesFilter : Binding msg -> Bool
        matchesFilter b =
            if not isFiltering then
                True

            else if String.startsWith "@" filter then
                let
                    keyFilter : String
                    keyFilter =
                        String.dropLeft 1 filter |> String.toLower
                in
                b.keys
                    |> List.any
                        (\k ->
                            formatKey k.key k.modifiers
                                |> String.toLower
                                |> String.contains keyFilter
                        )

            else
                String.toLower b.description
                    |> String.contains (String.toLower filter)
    in
    groups
        |> List.map (\g -> { g | bindings = List.filter matchesFilter g.bindings })
        |> List.filter (\g -> not (List.isEmpty g.bindings))


{-| Like `helpRows` but highlights the binding at the given index.
Pass -1 for no selection. Used by the help modal's browse mode.
-}
helpRowsWithSelection : Int -> String -> List (Group msg) -> List Tui.Screen.Screen
helpRowsWithSelection selectedIdx filter groups =
    let
        isFiltering : Bool
        isFiltering =
            not (String.isEmpty filter)

        fGroups : List (Group msg)
        fGroups =
            filteredBindings filter groups

        -- Right-align key labels: find max width across all visible bindings
        maxKeyWidth : Int
        maxKeyWidth =
            fGroups
                |> List.concatMap .bindings
                |> List.map (\b -> String.length (formatBinding b))
                |> List.maximum
                |> Maybe.withDefault 0

        cyanStyle : Tui.Screen.Style
        cyanStyle =
            { plain | fg = Just Ansi.Color.cyan }

        selectedStyle : Tui.Screen.Style
        selectedStyle =
            { plain | fg = Just Ansi.Color.white, bg = Just Ansi.Color.blue, attributes = [ Tui.Screen.Bold ] }

        selectedKeyStyle : Tui.Screen.Style
        selectedKeyStyle =
            { plain | fg = Just Ansi.Color.cyan, bg = Just Ansi.Color.blue, attributes = [ Tui.Screen.Bold ] }

        sectionStyle : Tui.Screen.Style
        sectionStyle =
            { plain | fg = Just Ansi.Color.green, attributes = [ Tui.Screen.Bold ] }

        renderBinding : Int -> Binding msg -> Tui.Screen.Screen
        renderBinding bindingIdx b =
            let
                keyLabel : String
                keyLabel =
                    formatBinding b

                padding : String
                padding =
                    String.repeat (maxKeyWidth - String.length keyLabel) " "

                isSelected : Bool
                isSelected =
                    bindingIdx == selectedIdx
            in
            if isSelected then
                Tui.Screen.concat
                    [ Tui.Screen.styled selectedStyle "  "
                    , Tui.Screen.styled selectedKeyStyle (padding ++ keyLabel)
                    , Tui.Screen.styled selectedStyle "  "
                    , Tui.Screen.styled selectedStyle b.description
                    ]

            else
                Tui.Screen.concat
                    [ Tui.Screen.text "  "
                    , Tui.Screen.styled cyanStyle (padding ++ keyLabel)
                    , Tui.Screen.text "  "
                    , Tui.Screen.text b.description
                    ]

        renderSectionHeader : String -> Tui.Screen.Screen
        renderSectionHeader name =
            Tui.Screen.styled sectionStyle ("--- " ++ name ++ " ---")

        renderGroup : Bool -> Int -> Group msg -> ( List Tui.Screen.Screen, Int )
        renderGroup isFirst bindingOffset g =
            let
                separator : List Tui.Screen.Screen
                separator =
                    if isFirst then
                        []

                    else
                        [ Tui.Screen.text "" ]

                header : List Tui.Screen.Screen
                header =
                    if isFiltering then
                        []

                    else
                        [ renderSectionHeader g.name ]

                bindingRows : List Tui.Screen.Screen
                bindingRows =
                    g.bindings
                        |> List.indexedMap
                            (\i b -> renderBinding (bindingOffset + i) b)
            in
            ( separator ++ header ++ bindingRows
            , bindingOffset + List.length g.bindings
            )
    in
    fGroups
        |> List.foldl
            (\g ( accRows, isFirst, offset ) ->
                let
                    ( rows, newOffset ) =
                        renderGroup isFirst offset g
                in
                ( accRows ++ rows, False, newOffset )
            )
            ( [], True, 0 )
        |> (\( rows, _, _ ) -> rows)


{-| A display-only help row with the same two-column formatting as binding rows.
Use this for mouse interactions, framework behaviors, or other non-keyboard
entries in the help screen. These are not dispatchable — they're informational.

    Keybinding.infoRow "scroll ↑" "Scroll up"
    Keybinding.infoRow "click" "Select item"

-}
infoRow : String -> String -> Tui.Screen.Screen
infoRow keyLabel description =
    Tui.Screen.concat
        [ Tui.Screen.text "  "
        , Tui.Screen.styled { plain | fg = Just Ansi.Color.cyan } keyLabel
        , Tui.Screen.text "  "
        , Tui.Screen.text description
        ]


{-| A bold green section header for grouping help entries.

    Keybinding.sectionHeader "Navigation"

-}
sectionHeader : String -> Tui.Screen.Screen
sectionHeader name =
    Tui.Screen.styled { plain | fg = Just Ansi.Color.green, attributes = [ Tui.Screen.Bold ] }
        ("--- " ++ name ++ " ---")
