module Tui.Picker exposing
    ( State, Config, open
    , typeChar, backspace, navigateDown, navigateUp
    , selected, visibleItems, query, matchCount, title
    , viewBody, viewBodyWithMaxRows, viewFooter
    )

{-| Searchable picker popup — present a filterable list for the user to
choose from. Supports fuzzy matching, j/k navigation, and match count.

For a menu where keys fire actions directly (no search), see [`Tui.Menu`](Tui-Menu).
For a command palette that combines Picker with keybinding display, see
[`Tui.CommandPalette`](Tui-CommandPalette). When using [`Layout.compileApp`](Tui-Layout#compileApp),
prefer [`Layout.pickerModal`](Tui-Layout#pickerModal) which handles key routing for you.

    -- Open a picker:
    Picker.open
        { items = modules
        , toString = .name
        , title = "Jump to..."
        }

    -- In update (handle key events while picker is open):
    case event.key of
        Tui.Sub.Escape -> closePicker
        Tui.Sub.Enter -> selectItem (Picker.selected pickerState)
        Tui.Sub.Arrow Tui.Sub.Down -> { model | picker = Picker.navigateDown model.picker }
        Tui.Sub.Arrow Tui.Sub.Up -> { model | picker = Picker.navigateUp model.picker }
        Tui.Sub.Backspace -> { model | picker = Picker.backspace model.picker }
        Tui.Sub.Character c -> { model | picker = Picker.typeChar c model.picker }

    -- Render with Modal.overlay:
    Modal.overlay
        { title = Picker.title pickerState
        , body = Picker.viewBodyWithMaxRows (Modal.maxBodyRows ctx.height) pickerState
        , footer = String.fromInt (Picker.matchCount pickerState) ++ " matches"
        , width = 50
        }
        dims bgRows

@docs State, Config, open
@docs typeChar, backspace, navigateDown, navigateUp
@docs selected, visibleItems, query, matchCount, title
@docs viewBody, viewBodyWithMaxRows, viewFooter

-}

import Ansi.Color
import Tui
import Tui.FuzzyMatch as FuzzyMatch
import Tui.Screen
import Tui.Sub


{-| Configuration for opening a picker.
-}
type alias Config item =
    { items : List item
    , toString : item -> String
    , title : String
    }


{-| Opaque picker state.
-}
type State item
    = State
        { allItems : List item
        , toString : item -> String
        , filterText : String
        , selectedIndex : Int
        , pickerTitle : String
        }


{-| Open a picker with the given config.
-}
open : Config item -> State item
open config =
    State
        { allItems = config.items
        , toString = config.toString
        , filterText = ""
        , selectedIndex = 0
        , pickerTitle = config.title
        }


{-| Type a character into the filter input.
-}
typeChar : Char -> State item -> State item
typeChar c (State s) =
    State
        { s
            | filterText = s.filterText ++ String.fromChar c
            , selectedIndex = 0
        }


{-| Delete the last character from the filter.
-}
backspace : State item -> State item
backspace (State s) =
    State
        { s
            | filterText = String.dropRight 1 s.filterText
            , selectedIndex = 0
        }


{-| Move selection down.
-}
navigateDown : State item -> State item
navigateDown (State s) =
    let
        maxIdx =
            max 0 (List.length (getVisibleItems s) - 1)
    in
    State { s | selectedIndex = min maxIdx (s.selectedIndex + 1) }


{-| Move selection up.
-}
navigateUp : State item -> State item
navigateUp (State s) =
    State { s | selectedIndex = max 0 (s.selectedIndex - 1) }


{-| Get the currently highlighted item.
-}
selected : State item -> Maybe item
selected (State s) =
    getVisibleItems s
        |> List.drop s.selectedIndex
        |> List.head


{-| Get the filtered/sorted list of visible items.
-}
visibleItems : State item -> List item
visibleItems (State s) =
    getVisibleItems s


{-| Get the current filter text.
-}
query : State item -> String
query (State s) =
    s.filterText


{-| Get the number of visible (matching) items.
-}
matchCount : State item -> Int
matchCount (State s) =
    List.length (getVisibleItems s)


{-| Get the picker title.
-}
title : State item -> String
title (State s) =
    s.pickerTitle


{-| Render the picker body (filter input + item list). Use as the `body`
of a `Tui.Modal.overlay`.
-}
viewBody : State item -> List Tui.Screen.Screen
viewBody (State s) =
    let
        ( headerRows, itemRows ) =
            pickerBodyRows s
    in
    headerRows ++ itemRows


{-| Render the picker body clamped to a maximum number of rows, keeping the
selected item visible.

This is the preferred rendering helper for long pickers in modals:

    Modal.overlay
        { title = Picker.title pickerState
        , body = Picker.viewBodyWithMaxRows (Modal.maxBodyRows ctx.height) pickerState
        , footer = Picker.viewFooter pickerState
        , width = Modal.defaultWidth ctx.width
        }
        dims
        bgRows

If the picker is shorter than `maxRows`, all rows are returned unchanged. If it
overflows, the returned list is padded so the modal height stays stable near the
end of the list.

-}
viewBodyWithMaxRows : Int -> State item -> List Tui.Screen.Screen
viewBodyWithMaxRows maxRows (State s) =
    let
        ( headerRows, itemRows ) =
            pickerBodyRows s

        visibleItemRows : Int
        visibleItemRows =
            max 0 (maxRows - List.length headerRows)

        scrollPadding : Int
        scrollPadding =
            if visibleItemRows > 2 then
                1

            else
                0

        scrollOffset : Int
        scrollOffset =
            scrollOffsetForSelectedRow s.selectedIndex visibleItemRows (List.length itemRows) scrollPadding

        windowedItemRows : List Tui.Screen.Screen
        windowedItemRows =
            if visibleItemRows <= 0 then
                []

            else
                itemRows
                    |> List.drop scrollOffset
                    |> List.take visibleItemRows

        paddedItemRows : List Tui.Screen.Screen
        paddedItemRows =
            if List.length itemRows > visibleItemRows && List.length windowedItemRows < visibleItemRows then
                windowedItemRows
                    ++ List.repeat (visibleItemRows - List.length windowedItemRows) Tui.Screen.empty

            else
                windowedItemRows
    in
    if maxRows <= 0 then
        []

    else if maxRows == 1 then
        List.take 1 headerRows

    else if List.length headerRows + List.length itemRows <= maxRows then
        headerRows ++ itemRows

    else
        headerRows ++ paddedItemRows


{-| Render a footer string showing match count.
-}
viewFooter : State item -> String
viewFooter (State s) =
    let
        count =
            List.length (getVisibleItems s)

        total =
            List.length s.allItems
    in
    String.fromInt count ++ "/" ++ String.fromInt total ++ " │ Enter: select │ Esc: cancel"



-- INTERNAL


getVisibleItems :
    { a | allItems : List item, toString : item -> String, filterText : String }
    -> List item
getVisibleItems s =
    if String.isEmpty s.filterText then
        s.allItems

    else
        s.allItems
            |> List.filterMap
                (\item ->
                    let
                        label =
                            s.toString item
                    in
                    if FuzzyMatch.match s.filterText label then
                        Just ( FuzzyMatch.score s.filterText label, item )

                    else
                        Nothing
                )
            |> List.sortBy (\( sc, _ ) -> negate sc)
            |> List.map Tuple.second


pickerBodyRows :
    { a
        | filterText : String
        , selectedIndex : Int
        , toString : item -> String
        , allItems : List item
    }
    -> ( List Tui.Screen.Screen, List Tui.Screen.Screen )
pickerBodyRows s =
    let
        items =
            getVisibleItems s

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

        itemRows =
            items
                |> List.indexedMap
                    (\i item ->
                        let
                            label =
                                s.toString item

                            isSelected =
                                i == s.selectedIndex
                        in
                        if isSelected then
                            Tui.Screen.text (" " ++ label ++ " ")
                                |> Tui.Screen.fg Ansi.Color.white
                                |> Tui.Screen.bg Ansi.Color.blue
                                |> Tui.Screen.bold

                        else
                            case FuzzyMatch.highlight s.filterText label of
                                Just segments ->
                                    Tui.Screen.concat
                                        (Tui.Screen.text " "
                                            :: List.map
                                                (\seg ->
                                                    if seg.matched then
                                                        Tui.Screen.text seg.text |> Tui.Screen.fg Ansi.Color.cyan |> Tui.Screen.bold

                                                    else
                                                        Tui.Screen.text seg.text
                                                )
                                                segments
                                        )

                                Nothing ->
                                    Tui.Screen.text (" " ++ label)
                    )
    in
    ( [ filterRow, Tui.Screen.blank ], itemRows )


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
