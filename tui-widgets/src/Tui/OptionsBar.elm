module Tui.OptionsBar exposing (view)

{-| Context-sensitive options bar — shows [`Tui.Keybinding`](Tui-Keybinding)
hints at the bottom of the screen. Like lazygit's bottom bar:

    Stage: <space> | Commit: c | Push: P | Keybindings: ?

Automatically truncates with `…` when the bar is too wide.

    -- In view, render as the last row:
    Tui.Screen.lines
        (layoutRows
            ++ [ OptionsBar.view ctx.width (activeBindings model) ]
        )

@docs view

-}

import Ansi.Color
import Tui
import Tui.Keybinding as Keybinding
import Tui.Screen


{-| Render the options bar for the given terminal width and keybinding groups.
Shows `description: key` pairs separated by ` | `. Truncates with `…` when
the bar would exceed the available width.

Uses the full binding label for each keybinding, including alternates and
modifiers (for example `j/↓` or `ctrl+s`).

-}
view : Int -> List (Keybinding.Group action) -> Tui.Screen.Screen
view maxWidth groups =
    let
        entries : List { description : String, key : String }
        entries =
            groups
                |> List.concatMap .bindings
                |> List.map
                    (\binding ->
                        { description = binding.description
                        , key = Keybinding.formatBinding binding
                        }
                    )

        separator : String
        separator =
            " | "

        truncated : List (Maybe { description : String, key : String })
        truncated =
            truncateEntries maxWidth separator entries
    in
    if List.isEmpty truncated then
        Tui.Screen.empty

    else
        truncated
            |> List.map renderEntry
            |> List.intersperse (Tui.Screen.text separator |> Tui.Screen.dim)
            |> Tui.Screen.concat


{-| Truncate entries to fit within maxWidth, appending "…" if needed.
-}
truncateEntries :
    Int
    -> String
    -> List { description : String, key : String }
    -> List (Maybe { description : String, key : String })
truncateEntries maxWidth separator entries =
    let
        sepLen : Int
        sepLen =
            String.length separator

        entryWidth : { description : String, key : String } -> Int
        entryWidth entry =
            String.length entry.description + 2 + String.length entry.key

        addEntry :
            { description : String, key : String }
            ->
                { acc : List (Maybe { description : String, key : String })
                , usedWidth : Int
                , isDone : Bool
                }
            ->
                { acc : List (Maybe { description : String, key : String })
                , usedWidth : Int
                , isDone : Bool
                }
        addEntry entry state =
            let
                entryLen : Int
                entryLen =
                    entryWidth entry

                totalWithSep : Int
                totalWithSep =
                    if List.isEmpty state.acc then
                        entryLen

                    else
                        state.usedWidth + sepLen + entryLen
            in
            if state.isDone then
                state

            else if totalWithSep <= maxWidth then
                { state | acc = state.acc ++ [ Just entry ], usedWidth = totalWithSep }

            else if List.isEmpty state.acc then
                if maxWidth >= 1 then
                    { acc = [ Nothing ], usedWidth = 1, isDone = True }

                else
                    { state | isDone = True }

            else if state.usedWidth + sepLen + 1 <= maxWidth then
                { acc = state.acc ++ [ Nothing ], usedWidth = state.usedWidth + sepLen + 1, isDone = True }

            else
                { state | isDone = True }
    in
    entries
        |> List.foldl addEntry { acc = [], usedWidth = 0, isDone = False }
        |> .acc


renderEntry : Maybe { description : String, key : String } -> Tui.Screen.Screen
renderEntry entry =
    case entry of
        Just fullEntry ->
            Tui.Screen.concat
                [ Tui.Screen.text fullEntry.description
                    |> Tui.Screen.dim
                , Tui.Screen.text ": "
                    |> Tui.Screen.dim
                , Tui.Screen.text fullEntry.key
                    |> Tui.Screen.fg Ansi.Color.cyan
                ]

        Nothing ->
            Tui.Screen.text "…" |> Tui.Screen.dim
