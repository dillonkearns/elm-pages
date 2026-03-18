module Tui.Keybinding exposing
    ( Binding, binding, withAlternate, withModifiers
    , Group, group
    , dispatch
    , formatKey, formatBinding
    , helpRows, helpRowsWithSelection, helpRowCount
    , infoRow, sectionHeader
    )

{-| Declarative keybinding system with scoped dispatch and auto-generated help.

Inspired by lazygit's keybinding architecture: bindings are data (not just
pattern matches), grouped into named scopes, dispatched in priority order,
and rendered as a searchable help screen.

    -- Declare bindings
    globalBindings =
        Keybinding.group "Global"
            [ Keybinding.binding (Tui.Character 'q') "Quit" Quit
            , Keybinding.binding (Tui.Character '?') "Help" ToggleHelp
            ]

    commitBindings =
        Keybinding.group "Commits"
            [ Keybinding.binding (Tui.Character 'j') "Next commit" (Navigate 1)
                |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
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


{-| A keybinding: one or more key combinations mapped to an action.
-}
type alias Binding msg =
    { keys : List { key : Tui.Key, modifiers : List Tui.Modifier }
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

    Keybinding.binding (Tui.Character 'q') "Quit" Quit

-}
binding : Tui.Key -> String -> msg -> Binding msg
binding key desc action =
    { keys = [ { key = key, modifiers = [] } ]
    , description = desc
    , action = action
    }


{-| Add an alternate key to a binding. The help screen shows both keys
separated by `/` (e.g., `j/↓`).

    Keybinding.binding (Tui.Character 'j') "Next" NavigateDown
        |> Keybinding.withAlternate (Tui.Arrow Tui.Down)

-}
withAlternate : Tui.Key -> Binding msg -> Binding msg
withAlternate key b =
    { b | keys = b.keys ++ [ { key = key, modifiers = [] } ] }


{-| Create a binding with modifier keys.

    Keybinding.withModifiers [ Tui.Ctrl ] (Tui.Character 's') "Save" Save

-}
withModifiers : List Tui.Modifier -> Tui.Key -> String -> msg -> Binding msg
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
dispatch : List (Group msg) -> Tui.KeyEvent -> Maybe msg
dispatch groups event =
    groups
        |> List.concatMap .bindings
        |> findMatch event


findMatch : Tui.KeyEvent -> List (Binding msg) -> Maybe msg
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


matchModifiers : List Tui.Modifier -> List Tui.Modifier -> Bool
matchModifiers expected actual =
    List.sort (List.map modifierOrder expected)
        == List.sort (List.map modifierOrder actual)


modifierOrder : Tui.Modifier -> Int
modifierOrder mod =
    case mod of
        Tui.Ctrl ->
            0

        Tui.Alt ->
            1

        Tui.Shift ->
            2



-- KEY FORMATTING


{-| Format a key and modifiers as a human-readable label.

    formatKey (Tui.Character 'j') [] == "j"
    formatKey (Tui.Arrow Tui.Up) [] == "↑"
    formatKey (Tui.Character 'a') [ Tui.Ctrl ] == "ctrl+a"

-}
formatKey : Tui.Key -> List Tui.Modifier -> String
formatKey key modifiers =
    let
        modPrefix : String
        modPrefix =
            modifiers
                |> List.map
                    (\m ->
                        case m of
                            Tui.Ctrl ->
                                "ctrl+"

                            Tui.Alt ->
                                "alt+"

                            Tui.Shift ->
                                "shift+"
                    )
                |> String.concat

        keyStr : String
        keyStr =
            case key of
                Tui.Character ' ' ->
                    "space"

                Tui.Character c ->
                    String.fromChar c

                Tui.Enter ->
                    "enter"

                Tui.Escape ->
                    "esc"

                Tui.Tab ->
                    "tab"

                Tui.Backspace ->
                    "backspace"

                Tui.Delete ->
                    "delete"

                Tui.Arrow Tui.Up ->
                    "↑"

                Tui.Arrow Tui.Down ->
                    "↓"

                Tui.Arrow Tui.Left ->
                    "←"

                Tui.Arrow Tui.Right ->
                    "→"

                Tui.Home ->
                    "home"

                Tui.End ->
                    "end"

                Tui.PageUp ->
                    "pgup"

                Tui.PageDown ->
                    "pgdn"

                Tui.FunctionKey n ->
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
helpRows : String -> List (Group msg) -> List Tui.Screen
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
helpRowsWithSelection : Int -> String -> List (Group msg) -> List Tui.Screen
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

        cyanStyle : Tui.Style
        cyanStyle =
            { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [] }

        selectedStyle : Tui.Style
        selectedStyle =
            { fg = Just Ansi.Color.white, bg = Just Ansi.Color.blue, attributes = [ Tui.Bold ] }

        selectedKeyStyle : Tui.Style
        selectedKeyStyle =
            { fg = Just Ansi.Color.cyan, bg = Just Ansi.Color.blue, attributes = [ Tui.Bold ] }

        sectionStyle : Tui.Style
        sectionStyle =
            { fg = Just Ansi.Color.green, bg = Nothing, attributes = [ Tui.Bold ] }

        renderBinding : Int -> Binding msg -> Tui.Screen
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
                Tui.concat
                    [ Tui.styled selectedStyle "  "
                    , Tui.styled selectedKeyStyle (padding ++ keyLabel)
                    , Tui.styled selectedStyle "  "
                    , Tui.styled selectedStyle b.description
                    ]

            else
                Tui.concat
                    [ Tui.text "  "
                    , Tui.styled cyanStyle (padding ++ keyLabel)
                    , Tui.text "  "
                    , Tui.text b.description
                    ]

        renderSectionHeader : String -> Tui.Screen
        renderSectionHeader name =
            Tui.styled sectionStyle ("--- " ++ name ++ " ---")

        renderGroup : Bool -> Int -> Group msg -> ( List Tui.Screen, Int )
        renderGroup isFirst bindingOffset g =
            let
                separator : List Tui.Screen
                separator =
                    if isFirst then
                        []

                    else
                        [ Tui.text "" ]

                header : List Tui.Screen
                header =
                    if isFiltering then
                        []

                    else
                        [ renderSectionHeader g.name ]

                bindingRows : List Tui.Screen
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
infoRow : String -> String -> Tui.Screen
infoRow keyLabel description =
    Tui.concat
        [ Tui.text "  "
        , Tui.styled { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [] } keyLabel
        , Tui.text "  "
        , Tui.text description
        ]


{-| A bold green section header for grouping help entries.

    Keybinding.sectionHeader "Navigation"

-}
sectionHeader : String -> Tui.Screen
sectionHeader name =
    Tui.styled { fg = Just Ansi.Color.green, bg = Nothing, attributes = [ Tui.Bold ] }
        ("--- " ++ name ++ " ---")
