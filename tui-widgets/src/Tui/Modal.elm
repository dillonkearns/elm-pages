module Tui.Modal exposing (overlay)

{-| Modal overlay for TUI layouts.

Renders a centered bordered dialog on top of background rows,
with the background visible on the left and right edges — like lazygit's
popup system.

    bgRows = Layout.toRows state layout
    Tui.Modal.overlay
        { title = "Commit"
        , body = [ Input.view { width = 40 } inputState ]
        , footer = "Enter: confirm"
        , width = 50
        }
        { width = ctx.width, height = ctx.height }
        bgRows

@docs overlay

-}

import Ansi.Color
import Tui exposing (plain)


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
        -- Clamp body to fit terminal: reserve 2 rows for top/bottom borders
        maxBodyRows : Int
        maxBodyRows =
            max 0 (term.height - 2)

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
