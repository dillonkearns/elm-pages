module Tui.CommandPalette exposing
    ( State, open
    , typeChar, backspace, navigateDown, navigateUp
    , selected, viewBody, viewBodyWithMaxRows, viewFooter, title
    )

{-| Command palette — browse and execute keybinding actions in one step.
Built on [`Tui.Picker`](Tui-Picker) and [`Tui.Keybinding`](Tui-Keybinding).

    -- Open with current keybinding groups:
    CommandPalette.open (activeBindings model)

    -- In update:
    case event.key of
        Tui.Event.Escape -> closeCommandPalette
        Tui.Event.Enter ->
            case CommandPalette.selected model.palette of
                Just action -> handleAction action model
                Nothing -> ( model, Effect.none )
        Tui.Event.Backspace -> { model | palette = CommandPalette.backspace model.palette }
        Tui.Event.Character c -> { model | palette = CommandPalette.typeChar c model.palette }
        Tui.Event.Arrow Tui.Event.Down -> { model | palette = CommandPalette.navigateDown model.palette }
        Tui.Event.Arrow Tui.Event.Up -> { model | palette = CommandPalette.navigateUp model.palette }

    -- Render with Modal.overlay:
    Modal.overlay
        { title = CommandPalette.title
        , body = CommandPalette.viewBodyWithMaxRows (Modal.maxBodyRows ctx.height) model.palette
        , footer = CommandPalette.viewFooter model.palette
        , width = 50
        }
        dims bgRows

@docs State, open
@docs typeChar, backspace, navigateDown, navigateUp
@docs selected, viewBody, viewBodyWithMaxRows, viewFooter, title

-}

import Ansi.Color
import Tui
import Tui.Event
import Tui.FuzzyMatch as FuzzyMatch
import Tui.Keybinding as Keybinding
import Tui.Screen


{-| Opaque command palette state.
-}
type State action
    = State
        { entries : List (Entry action)
        , filterText : String
        , selectedIndex : Int
        }


type alias Entry action =
    { keyLabel : String
    , description : String
    , action : action
    }


{-| Open the command palette with keybinding groups.
-}
open : List (Keybinding.Group action) -> State action
open groups =
    State
        { entries =
            groups
                |> List.concatMap
                    (\group ->
                        group.bindings
                            |> List.map
                                (\binding ->
                                    { keyLabel = Keybinding.formatBinding binding
                                    , description = binding.description
                                    , action = binding.action
                                    }
                                )
                    )
        , filterText = ""
        , selectedIndex = 0
        }


{-| Type a character into the filter.
-}
typeChar : Char -> State action -> State action
typeChar c (State s) =
    State { s | filterText = s.filterText ++ String.fromChar c, selectedIndex = 0 }


{-| Delete the last character.
-}
backspace : State action -> State action
backspace (State s) =
    State { s | filterText = String.dropRight 1 s.filterText, selectedIndex = 0 }


{-| Move selection down.
-}
navigateDown : State action -> State action
navigateDown (State s) =
    let
        maxIdx =
            max 0 (List.length (getVisible s) - 1)
    in
    State { s | selectedIndex = min maxIdx (s.selectedIndex + 1) }


{-| Move selection up.
-}
navigateUp : State action -> State action
navigateUp (State s) =
    State { s | selectedIndex = max 0 (s.selectedIndex - 1) }


{-| Get the selected action.
-}
selected : State action -> Maybe action
selected (State s) =
    getVisible s
        |> List.drop s.selectedIndex
        |> List.head
        |> Maybe.map .action


{-| The palette title.
-}
title : String
title =
    "Actions"


{-| Render the palette body.
-}
viewBody : State action -> List Tui.Screen.Screen
viewBody (State s) =
    let
        ( headerRows, entryRows ) =
            paletteBodyRows s
    in
    headerRows ++ entryRows


{-| Render the palette body clamped to a maximum number of rows, keeping the
selected action visible.

This is the preferred rendering helper for long command palettes in modals:

    Modal.overlay
        { title = CommandPalette.title
        , body = CommandPalette.viewBodyWithMaxRows (Modal.maxBodyRows ctx.height) paletteState
        , footer = CommandPalette.viewFooter paletteState
        , width = Modal.defaultWidth ctx.width
        }
        dims
        bgRows

If the palette is shorter than `maxRows`, all rows are returned unchanged. If it
overflows, the returned list is padded so the modal height stays stable near the
end of the list.

-}
viewBodyWithMaxRows : Int -> State action -> List Tui.Screen.Screen
viewBodyWithMaxRows maxRows (State s) =
    let
        ( headerRows, entryRows ) =
            paletteBodyRows s

        visibleEntryRows : Int
        visibleEntryRows =
            max 0 (maxRows - List.length headerRows)

        scrollPadding : Int
        scrollPadding =
            if visibleEntryRows > 2 then
                1

            else
                0

        scrollOffset : Int
        scrollOffset =
            scrollOffsetForSelectedRow s.selectedIndex visibleEntryRows (List.length entryRows) scrollPadding

        windowedEntryRows : List Tui.Screen.Screen
        windowedEntryRows =
            if visibleEntryRows <= 0 then
                []

            else
                entryRows
                    |> List.drop scrollOffset
                    |> List.take visibleEntryRows

        paddedEntryRows : List Tui.Screen.Screen
        paddedEntryRows =
            if List.length entryRows > visibleEntryRows && List.length windowedEntryRows < visibleEntryRows then
                windowedEntryRows
                    ++ List.repeat (visibleEntryRows - List.length windowedEntryRows) Tui.Screen.empty

            else
                windowedEntryRows
    in
    if maxRows <= 0 then
        []

    else if maxRows == 1 then
        List.take 1 headerRows

    else if List.length headerRows + List.length entryRows <= maxRows then
        headerRows ++ entryRows

    else
        headerRows ++ paddedEntryRows


{-| Render a footer string.
-}
viewFooter : State action -> String
viewFooter (State s) =
    let
        count =
            List.length (getVisible s)
    in
    String.fromInt count ++ " actions │ Enter: execute │ Esc: cancel"



-- INTERNAL


getVisible : { a | entries : List (Entry action), filterText : String } -> List (Entry action)
getVisible s =
    if String.isEmpty s.filterText then
        s.entries

    else
        s.entries
            |> List.filterMap
                (\entry ->
                    if FuzzyMatch.match s.filterText entry.description then
                        Just ( FuzzyMatch.score s.filterText entry.description, entry )

                    else if FuzzyMatch.match s.filterText entry.keyLabel then
                        Just ( FuzzyMatch.score s.filterText entry.keyLabel, entry )

                    else
                        Nothing
                )
            |> List.sortBy (\( sc, _ ) -> negate sc)
            |> List.map Tuple.second


paletteBodyRows :
    { a
        | entries : List (Entry action)
        , filterText : String
        , selectedIndex : Int
    }
    -> ( List Tui.Screen.Screen, List Tui.Screen.Screen )
paletteBodyRows s =
    let
        entries =
            getVisible s

        filterRow =
            Tui.Screen.concat
                [ Tui.Screen.text "/ " |> Tui.Screen.dim
                , if String.isEmpty s.filterText then
                    Tui.Screen.text " " |> Tui.Screen.inverse

                  else
                    Tui.Screen.concat
                        [ Tui.Screen.text s.filterText
                        , Tui.Screen.text " " |> Tui.Screen.inverse
                        ]
                ]

        entryRows =
            entries
                |> List.indexedMap
                    (\i entry ->
                        let
                            isSelected =
                                i == s.selectedIndex
                        in
                        if isSelected then
                            Tui.Screen.concat
                                [ Tui.Screen.text entry.keyLabel |> Tui.Screen.fg Ansi.Color.cyan |> Tui.Screen.bold
                                , Tui.Screen.text " "
                                , Tui.Screen.text entry.description
                                ]
                                |> Tui.Screen.bg Ansi.Color.blue

                        else
                            Tui.Screen.concat
                                [ Tui.Screen.text entry.keyLabel |> Tui.Screen.fg Ansi.Color.cyan
                                , Tui.Screen.text " "
                                , Tui.Screen.text entry.description
                                ]
                    )
    in
    ( [ filterRow, Tui.Screen.blank ], entryRows )


scrollOffsetForSelectedRow : Int -> Int -> Int -> Int -> Int
scrollOffsetForSelectedRow selectedRow visibleRows totalRows padding =
    let
        maxOffset : Int
        maxOffset =
            max 0 (totalRows - visibleRows)
    in
    if visibleRows <= 0 then
        0

    else if selectedRow < padding then
        0

    else if selectedRow > visibleRows - 1 - padding then
        clamp 0 maxOffset (selectedRow - visibleRows + 1 + padding)

    else
        0
