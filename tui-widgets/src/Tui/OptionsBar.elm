module Tui.OptionsBar exposing (view)

{-| Context-sensitive options bar — shows keybinding hints at the bottom
of the screen. Inspired by lazygit's bottom bar:

    Stage: <space> | Commit: c | Push: P | Keybindings: ?

Automatically truncates with `…` when the bar is too wide.

    -- In view, render as the last row:
    Tui.lines
        (layoutRows
            ++ [ OptionsBar.view ctx.width (activeBindings model) ]
        )

@docs view

-}

import Ansi.Color
import Tui
import Tui.Keybinding as Keybinding


{-| Render the options bar for the given terminal width and keybinding groups.
Shows `description: key` pairs separated by ` | `. Truncates with `…` when
the bar would exceed the available width.

Uses the first key of each binding for the display.

-}
view : Int -> List (Keybinding.Group action) -> Tui.Screen
view maxWidth groups =
    let
        entries : List { description : String, key : String }
        entries =
            groups
                |> List.concatMap .bindings
                |> List.map
                    (\binding ->
                        { description = binding.description
                        , key =
                            binding.keys
                                |> List.head
                                |> Maybe.map (\k -> Keybinding.formatKey k.key k.modifiers)
                                |> Maybe.withDefault "?"
                        }
                    )

        separator : String
        separator =
            " | "

        formatEntry : { description : String, key : String } -> String
        formatEntry entry =
            entry.description ++ ": " ++ entry.key

        truncated : List String
        truncated =
            truncateEntries maxWidth separator (List.map formatEntry entries)
    in
    if List.isEmpty truncated then
        Tui.empty

    else
        truncated
            |> List.map
                (\entry ->
                    Tui.concat
                        [ Tui.text (String.split ": " entry |> List.head |> Maybe.withDefault entry)
                            |> Tui.dim
                        , Tui.text ": "
                            |> Tui.dim
                        , Tui.text (String.split ": " entry |> List.drop 1 |> String.join ": ")
                            |> Tui.fg Ansi.Color.cyan
                        ]
                )
            |> List.intersperse (Tui.text separator |> Tui.dim)
            |> Tui.concat


{-| Truncate entries to fit within maxWidth, appending "…" if needed.
-}
truncateEntries : Int -> String -> List String -> List String
truncateEntries maxWidth separator entries =
    let
        sepLen : Int
        sepLen =
            String.length separator

        addEntry : String -> ( List String, Int ) -> ( List String, Int )
        addEntry entry ( acc, usedWidth ) =
            let
                entryLen : Int
                entryLen =
                    String.length entry

                totalWithSep : Int
                totalWithSep =
                    if List.isEmpty acc then
                        entryLen

                    else
                        usedWidth + sepLen + entryLen
            in
            if totalWithSep <= maxWidth then
                ( acc ++ [ entry ], totalWithSep )

            else if usedWidth + sepLen + 1 <= maxWidth then
                -- Room for the ellipsis
                ( acc ++ [ "…" ], usedWidth + sepLen + 1 )

            else
                ( acc, usedWidth )
    in
    entries
        |> List.foldl addEntry ( [], 0 )
        |> Tuple.first
