module Tui.Screen exposing
    ( Span
    , toSpanLines, fromSpans
    , truncateSpans, wrapSpans
    )

{-| Advanced screen helpers for companion packages and tooling.

This module exposes a styled-span view of [`Tui.Screen`](Tui#Screen) without
leaking the raw internal representation used by the renderer.

Most apps do not need this module directly. It is useful when you need to
analyze or rebuild styled terminal content while preserving colors, text
attributes, and hyperlinks.

@docs Span
@docs toSpanLines, fromSpans
@docs truncateSpans, wrapSpans

-}

import Tui
import Tui.Screen.Internal as Internal


{-| A styled text segment from a rendered screen line.
-}
type alias Span =
    { text : String
    , style : Tui.Style
    }


{-| Flatten a `Tui.Screen` into styled span lines.
-}
toSpanLines : Tui.Screen -> List (List Span)
toSpanLines screen =
    Internal.flattenToSpanLines styleToFlatStyle screen
        |> List.map (List.map fromInternalSpan)


{-| Rebuild a `Tui.Screen` from styled spans.
-}
fromSpans : List Span -> Tui.Screen
fromSpans spans =
    spans
        |> List.map toInternalSpan
        |> Internal.spansToScreen flatStyleToStyle


{-| Truncate a span line to a maximum width, preserving styles.
-}
truncateSpans : Int -> List Span -> List Span
truncateSpans maxWidth spans =
    spans
        |> List.map toInternalSpan
        |> Internal.truncateSpans maxWidth
        |> List.map fromInternalSpan


{-| Wrap a span line to a maximum width, preserving styles.
-}
wrapSpans : Int -> List Span -> List (List Span)
wrapSpans maxWidth spans =
    spans
        |> List.map toInternalSpan
        |> Internal.wrapSpans maxWidth
        |> List.map (List.map fromInternalSpan)


toInternalSpan : Span -> Internal.Span
toInternalSpan span =
    { text = span.text
    , style = styleToFlatStyle span.style
    }


fromInternalSpan : Internal.Span -> Span
fromInternalSpan span =
    { text = span.text
    , style = flatStyleToStyle span.style
    }


styleToFlatStyle : Tui.Style -> Internal.FlatStyle
styleToFlatStyle style =
    let
        defaultStyle : Internal.FlatStyle
        defaultStyle =
            Internal.defaultFlatStyle

        base : Internal.FlatStyle
        base =
            { defaultStyle
                | foreground = style.fg
                , background = style.bg
                , hyperlink = style.hyperlink
            }
    in
    List.foldl applyAttribute base style.attributes


applyAttribute : Tui.Attribute -> Internal.FlatStyle -> Internal.FlatStyle
applyAttribute attribute flatStyle =
    case attribute of
        Tui.Bold ->
            { flatStyle | bold = True }

        Tui.Dim ->
            { flatStyle | dim = True }

        Tui.Italic ->
            { flatStyle | italic = True }

        Tui.Underline ->
            { flatStyle | underline = True }

        Tui.Strikethrough ->
            { flatStyle | strikethrough = True }

        Tui.Inverse ->
            { flatStyle | inverse = True }


flatStyleToStyle : Internal.FlatStyle -> Tui.Style
flatStyleToStyle flatStyle =
    { fg = flatStyle.foreground
    , bg = flatStyle.background
    , attributes =
        List.filterMap identity
            [ if flatStyle.bold then
                Just Tui.Bold

              else
                Nothing
            , if flatStyle.dim then
                Just Tui.Dim

              else
                Nothing
            , if flatStyle.italic then
                Just Tui.Italic

              else
                Nothing
            , if flatStyle.underline then
                Just Tui.Underline

              else
                Nothing
            , if flatStyle.strikethrough then
                Just Tui.Strikethrough

              else
                Nothing
            , if flatStyle.inverse then
                Just Tui.Inverse

              else
                Nothing
            ]
    , hyperlink = flatStyle.hyperlink
    }
