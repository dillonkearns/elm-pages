module Tui.Modal exposing (overlay, defaultWidth, maxBodyRows)

{-| Modal overlay for TUI layouts.

This is the rendering primitive used by [`Tui.Picker`](Tui-Picker),
[`Tui.Menu`](Tui-Menu), [`Tui.Confirm`](Tui-Confirm), and [`Tui.Prompt`](Tui-Prompt).
You can also use it directly for custom modal content.

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

@docs overlay, defaultWidth, maxBodyRows

-}

import Ansi.Color
import Tui
import Tui.Screen


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


{-| Calculate the maximum number of body rows that [`overlay`](#overlay)
will display for a terminal of the given height.

Useful when you want to pre-window modal content before passing it to
[`overlay`](#overlay):

    Modal.overlay
        { title = Menu.title
        , body = Menu.viewBodyWithMaxRows (Modal.maxBodyRows ctx.height) menuState
        , footer = "Esc: close"
        , width = Modal.defaultWidth ctx.width
        }
        { width = ctx.width, height = ctx.height }
        bgRows

-}
maxBodyRows : Int -> Int
maxBodyRows terminalHeight =
    max 0 ((terminalHeight * 3 // 4) - 2)


{-| Overlay a centered modal dialog on top of background rows.

Returns a `List Screen` (one per terminal row) suitable for `Tui.Screen.lines`.
Background rows above and below the modal pass through unchanged.
Modal-covered rows show: background left edge | modal | background right edge.

If the body content exceeds the terminal height, it is clamped to fit
(like lazygit's popup system). The title and footer borders are always
visible.

-}
overlay :
    { title : String
    , body : List Tui.Screen.Screen
    , footer : String
    , width : Int
    }
    -> { width : Int, height : Int }
    -> List Tui.Screen.Screen
    -> List Tui.Screen.Screen
overlay config term bgRows =
    let
        -- Clamp modal to 75% of terminal height (lazygit uses height * 3/4).
        -- Then subtract 2 for top/bottom borders to get max body rows.
        -- The remaining 25% ensures the background is visible around the modal.
        maxBodyRows_ : Int
        maxBodyRows_ =
            maxBodyRows term.height

        clampedBody : List Tui.Screen.Screen
        clampedBody =
            List.take maxBodyRows_ config.body

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

        borderStyling : Tui.Screen.Screen -> Tui.Screen.Screen
        borderStyling =
            Tui.Screen.fg Ansi.Color.green >> Tui.Screen.bold

        -- Composite a modal strip onto a background row:
        -- [background left edge] [modal content] [right fill]
        compositeRow : Tui.Screen.Screen -> Tui.Screen.Screen -> Tui.Screen.Screen
        compositeRow bgRow modalStrip =
            Tui.Screen.concat
                [ Tui.Screen.truncateWidth leftPad bgRow
                , modalStrip
                , Tui.Screen.text
                    (String.repeat (term.width - leftPad - modalWidth) " ")
                ]

        topBorder : Tui.Screen.Screen
        topBorder =
            let
                titleText : String
                titleText =
                    " " ++ config.title ++ " "

                fillLen : Int
                fillLen =
                    max 0 (innerWidth - String.length titleText)
            in
            Tui.Screen.concat
                [ Tui.Screen.text "╭" |> borderStyling
                , Tui.Screen.text titleText |> borderStyling
                , Tui.Screen.text (String.repeat fillLen "─") |> borderStyling
                , Tui.Screen.text "╮" |> borderStyling
                ]

        bottomBorder : Tui.Screen.Screen
        bottomBorder =
            let
                footerText : String
                footerText =
                    " " ++ config.footer ++ " "

                fillLen : Int
                fillLen =
                    max 0 (innerWidth - String.length footerText)
            in
            Tui.Screen.concat
                [ Tui.Screen.text "╰" |> borderStyling
                , Tui.Screen.text (String.repeat fillLen "─") |> borderStyling
                , Tui.Screen.text footerText |> borderStyling
                , Tui.Screen.text "╯" |> borderStyling
                ]

        bodyStrip : Tui.Screen.Screen -> Tui.Screen.Screen
        bodyStrip content =
            let
                contentText : String
                contentText =
                    Tui.Screen.toString content

                contentWidth : Int
                contentWidth =
                    String.length contentText

                padding : Int
                padding =
                    max 0 (innerWidth - contentWidth)
            in
            Tui.Screen.concat
                [ Tui.Screen.text "│" |> borderStyling
                , Tui.Screen.truncateWidth innerWidth content
                , Tui.Screen.text
                    (String.repeat padding " ")
                , Tui.Screen.text "│" |> borderStyling
                ]

        modalStrips : List Tui.Screen.Screen
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
