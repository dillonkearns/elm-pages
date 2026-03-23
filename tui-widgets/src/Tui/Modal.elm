module Tui.Modal exposing (overlay, defaultWidth)

{-| Modal overlay for TUI layouts.

Renders a centered bordered dialog on top of background rows,
with the background visible on the left and right edges — like lazygit's
popup system. Modal height is capped at 75% of terminal height.

    bgRows = Layout.toRows state layout
    Tui.Modal.overlay
        { title = "Commit"
        , body = [ Input.view { width = 40 } inputState ]
        , footer = "Enter: confirm"
        , width = Modal.defaultWidth ctx.width
        }
        { width = ctx.width, height = ctx.height }
        bgRows

@docs overlay, defaultWidth

-}

import Ansi.Color
import Tui exposing (plain)


{-| Calculate a good default modal width for the given terminal width.
Uses lazygit's formula: `min(4 * terminalWidth / 7, 90)` with a floor
of 80 characters (or `terminalWidth - 2` if the terminal is narrow).

    Modal.defaultWidth 120  -- 68 (120 * 4/7 = 68)
    Modal.defaultWidth 80   -- 80 (floor)
    Modal.defaultWidth 40   -- 38 (narrow terminal)

This is a convenience — you can always pass a custom `width` directly
if the default is too wide or too narrow for your content:

    Modal.overlay { ..., width = min 50 (ctx.width - 4) } ...

-}
defaultWidth : Int -> Int
defaultWidth termWidth =
    let
        calculated =
            min (4 * termWidth // 7) 90

        floored =
            if calculated < 80 then
                min (termWidth - 2) 80

            else
                calculated
    in
    max 10 floored


{-| Overlay a centered modal dialog on top of background rows.

Returns a `List Screen` (one per terminal row) suitable for `Tui.lines`.
Background rows above and below the modal pass through unchanged.
Modal-covered rows show: background left edge | modal | background right edge.

If the body content exceeds the terminal height, it is clamped to fit
(like lazygit's popup system). The title and footer borders are always
visible.

-}
overlay :
    { title : String
    , body : List Tui.Screen
    , footer : String
    , width : Int
    }
    -> { width : Int, height : Int }
    -> List Tui.Screen
    -> List Tui.Screen
overlay config term bgRows =
    let
        -- Clamp modal to 75% of terminal height (lazygit uses height * 3/4).
        -- Then subtract 2 for top/bottom borders to get max body rows.
        -- The remaining 25% ensures the background is visible around the modal.
        maxModalHeight : Int
        maxModalHeight =
            term.height * 3 // 4

        maxBodyRows : Int
        maxBodyRows =
            max 0 (maxModalHeight - 2)

        clampedBody : List Tui.Screen
        clampedBody =
            List.take maxBodyRows config.body

        modalHeight : Int
        modalHeight =
            List.length clampedBody + 2

        modalWidth : Int
        modalWidth =
            min config.width term.width

        innerWidth : Int
        innerWidth =
            modalWidth - 2

        startRow : Int
        startRow =
            (term.height - modalHeight) // 2

        leftPad : Int
        leftPad =
            (term.width - modalWidth) // 2

        borderStyle : Tui.Style
        borderStyle =
            { plain | fg = Just Ansi.Color.green, attributes = [ Tui.Bold ] }

        -- Composite a modal strip onto a background row:
        -- [background left edge] [modal content] [right fill]
        compositeRow : Tui.Screen -> Tui.Screen -> Tui.Screen
        compositeRow bgRow modalStrip =
            Tui.concat
                [ Tui.truncateWidth leftPad bgRow
                , modalStrip
                , Tui.styled plain
                    (String.repeat (term.width - leftPad - modalWidth) " ")
                ]

        topBorder : Tui.Screen
        topBorder =
            let
                titleText : String
                titleText =
                    " " ++ config.title ++ " "

                fillLen : Int
                fillLen =
                    max 0 (innerWidth - String.length titleText)
            in
            Tui.concat
                [ Tui.styled borderStyle "╭"
                , Tui.styled borderStyle titleText
                , Tui.styled borderStyle (String.repeat fillLen "─")
                , Tui.styled borderStyle "╮"
                ]

        bottomBorder : Tui.Screen
        bottomBorder =
            let
                footerText : String
                footerText =
                    " " ++ config.footer ++ " "

                fillLen : Int
                fillLen =
                    max 0 (innerWidth - String.length footerText)
            in
            Tui.concat
                [ Tui.styled borderStyle "╰"
                , Tui.styled borderStyle (String.repeat fillLen "─")
                , Tui.styled borderStyle footerText
                , Tui.styled borderStyle "╯"
                ]

        bodyStrip : Tui.Screen -> Tui.Screen
        bodyStrip content =
            let
                contentText : String
                contentText =
                    Tui.toString content

                contentWidth : Int
                contentWidth =
                    String.length contentText

                padding : Int
                padding =
                    max 0 (innerWidth - contentWidth)
            in
            Tui.concat
                [ Tui.styled borderStyle "│"
                , Tui.truncateWidth innerWidth content
                , Tui.styled plain
                    (String.repeat padding " ")
                , Tui.styled borderStyle "│"
                ]

        modalStrips : List Tui.Screen
        modalStrips =
            [ topBorder ]
                ++ List.map bodyStrip clampedBody
                ++ [ bottomBorder ]
    in
    List.indexedMap
        (\i bgRow ->
            if i >= startRow && i < startRow + modalHeight then
                let
                    modalIdx : Int
                    modalIdx =
                        i - startRow
                in
                modalStrips
                    |> List.drop modalIdx
                    |> List.head
                    |> Maybe.map (compositeRow bgRow)
                    |> Maybe.withDefault bgRow

            else
                bgRow
        )
        bgRows
