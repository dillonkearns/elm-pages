module Tui.Screen exposing
    ( Screen, text, lines, concat, empty, blank
    , fg, bg, bold, dim, italic, underline, strikethrough, inverse, withAttributes, link
    , Style
    , truncateWidth, wrapWidth
    , toString
    )

{-| Styled terminal output for a [`Tui.Program`](Tui#Program)'s `view` function.

    import Tui.Screen as Screen

    view : Tui.Context -> Model -> Screen.Screen
    view _ model =
        Screen.lines
            [ Screen.text "Hello, TUI!" |> Screen.bold
            , Screen.blank
            , Screen.text ("Count: " ++ String.fromInt model.count)
                |> Screen.fg Ansi.Color.cyan
            ]


## Building Screens

Screens compose vertically with [`lines`](#lines) and horizontally with
[`concat`](#concat). For split-pane layouts, see the `Tui.Layout` module in
the `tui-widgets` package.

@docs Screen, text, lines, concat, empty, blank


## Styling

Pipeline-style builders that compose on any `Screen` (text, concat, lines):

    Screen.text "warning" |> Screen.fg Ansi.Color.yellow |> Screen.bold

    Screen.concat [ a, b ] |> Screen.dim -- dims both a and b

For reusable styling, define a styling function and apply it to multiple
screens:

    borderStyling : Screen -> Screen
    borderStyling = Screen.fg Ansi.Color.gray >> Screen.bold

    Screen.text "|" |> borderStyling

@docs fg, bg, bold, dim, italic, underline, strikethrough, inverse, withAttributes, link

See [`Tui.Attribute`](Tui-Attribute) for the `Attribute` type used by
[`withAttributes`](#withAttributes).

@docs Style

`Style` is opaque so that future releases can add fields without breaking
user code. To inspect a `Style` obtained from a
[`Tui.Screen.Advanced.Span`](Tui-Screen-Advanced#Span), use the getter
functions in [`Tui.Screen.Advanced`](Tui-Screen-Advanced).


## Text Manipulation

@docs truncateWidth, wrapWidth


## Inspecting

@docs toString

For framework-level consumers that need to inspect rendered lines or rebuild
styled output, see [`Tui.Screen.Advanced`](Tui-Screen-Advanced).

-}

import Ansi.Color
import Tui.Attribute exposing (Attribute(..))
import Tui.Screen.Internal as Internal exposing (plain)



-- SCREEN


{-| Opaque type representing terminal output. Built from primitives, rendered by
the framework.
-}
type alias Screen =
    Internal.Screen Style


{-| Terminal cell style: foreground color, background color, text
attributes, and optional hyperlink.

Opaque so the field list can grow in future releases without breaking user
code. To build styled text, use the Screen-level builders
([`fg`](#fg), [`bold`](#bold), etc.) directly on a `Screen`. To read the
style of a [`Tui.Screen.Advanced.Span`](Tui-Screen-Advanced#Span), use
[`Tui.Screen.Advanced.styleForeground`](Tui-Screen-Advanced#styleForeground)
and friends.

-}
type alias Style =
    Internal.Style


{-| Unstyled text.
-}
text : String -> Screen
text =
    Internal.ScreenText


{-| Stack screens vertically. Each item starts on a new line.
-}
lines : List Screen -> Screen
lines =
    Internal.ScreenLines


{-| Concatenate screens horizontally, row by row. If one child has more lines
than another, the extra trailing lines are preserved.
-}
concat : List Screen -> Screen
concat =
    Internal.ScreenConcat


{-| Empty screen that renders nothing and takes up zero lines. Use this as
a "null" value, for example with `Maybe.withDefault`:

    case maybeError of
        Just err ->
            Screen.text err |> Screen.fg Ansi.Color.red

        Nothing ->
            Screen.empty

Note: this is different from [`blank`](#blank) which renders one empty line.
`empty` produces no output at all.

-}
empty : Screen
empty =
    Internal.ScreenEmpty


{-| A blank line that renders one empty line. Useful as a vertical spacer
in [`lines`](#lines):

    Screen.lines
        [ Screen.text "Title"
        , Screen.blank
        , Screen.text "Content"
        ]

Note: this is different from [`empty`](#empty) which renders nothing.
`blank` produces a visible gap (one empty row).

-}
blank : Screen
blank =
    Internal.ScreenText ""



-- STYLE BUILDERS


{-| Set foreground color on a Screen. Composes with pipeline syntax:

    Screen.text "error" |> Screen.fg Ansi.Color.red

    Screen.text "warning" |> Screen.fg Ansi.Color.yellow |> Screen.bold

-}
fg : Ansi.Color.Color -> Screen -> Screen
fg color screen =
    Internal.applyStyle plain (\(Internal.Style s) -> Internal.Style { s | fg = Just color }) screen


{-| Set background color on a Screen.

    Screen.text "selected" |> Screen.bg Ansi.Color.blue

-}
bg : Ansi.Color.Color -> Screen -> Screen
bg color screen =
    Internal.applyStyle plain (\(Internal.Style s) -> Internal.Style { s | bg = Just color }) screen


{-| Apply bold attribute.

    Screen.text "important" |> Screen.bold

-}
bold : Screen -> Screen
bold =
    addAttr Bold


{-| Apply dim attribute.

    Screen.text "muted" |> Screen.dim

-}
dim : Screen -> Screen
dim =
    addAttr Dim


{-| Apply italic attribute.
-}
italic : Screen -> Screen
italic =
    addAttr Italic


{-| Apply underline attribute.
-}
underline : Screen -> Screen
underline =
    addAttr Underline


{-| Apply strikethrough attribute.
-}
strikethrough : Screen -> Screen
strikethrough =
    addAttr Strikethrough


{-| Apply inverse (reverse video) attribute.
-}
inverse : Screen -> Screen
inverse =
    addAttr Inverse


{-| Wrap a Screen in a clickable hyperlink (OSC 8). In terminals that support it,
the text becomes a clickable link. In unsupported terminals, the escape sequence
is silently ignored and the text renders normally.

    Screen.text "elm/core"
        |> Screen.underline
        |> Screen.fg Ansi.Color.blue
        |> Screen.link { url = "https://package.elm-lang.org/packages/elm/core/latest" }

-}
link : { url : String } -> Screen -> Screen
link { url } =
    Internal.applyStyle plain (\(Internal.Style s) -> Internal.Style { s | hyperlink = Just url })


addAttr : Attribute -> Screen -> Screen
addAttr attr =
    Internal.applyStyle plain (\(Internal.Style s) -> Internal.Style { s | attributes = attr :: s.attributes })


{-| Apply a list of attributes at once. Useful when the attribute set is
dynamic (from a config, theme, or computed list). Equivalent to chaining the
individual builders.

    import Tui.Attribute as Attr
    import Tui.Screen as Screen

    Screen.text "Heading"
        |> Screen.withAttributes [ Attr.Bold, Attr.Underline ]

-}
withAttributes : List Attribute -> Screen -> Screen
withAttributes attrs screen =
    List.foldl addAttr screen attrs


flattenToSpanLines : Screen -> List (List Internal.Span)
flattenToSpanLines =
    Internal.flattenToSpanLines Internal.styleToFlatStyle



-- INSPECTING


{-| Convert a Screen to a plain text string (no ANSI codes). Useful for testing,
layout measurement, and debugging.
-}
toString : Screen -> String
toString screen =
    flattenToSpanLines screen
        |> List.map (\spans -> spans |> List.map .text |> String.concat)
        |> String.join "\n"


{-| Truncate a Screen to a maximum width in columns, preserving styles.
Adds "\\u{2026}" if truncated. Works on the first line only. Returns `empty`
for non-positive widths.
-}
truncateWidth : Int -> Screen -> Screen
truncateWidth maxWidth screen =
    if maxWidth <= 0 then
        empty

    else
        case flattenToSpanLines screen of
            [] ->
                empty

            first :: _ ->
                if List.isEmpty first then
                    blank

                else
                    let
                        truncated : List Internal.Span
                        truncated =
                            Internal.truncateSpans maxWidth first
                    in
                    case truncated of
                        [] ->
                            empty

                        _ ->
                            truncated
                                |> List.map (Internal.spanToScreen Internal.flatStyleToStyle)
                                |> Internal.ScreenConcat


{-| Wrap a Screen to a maximum width, preserving styles across line breaks.
Returns a list of Screens, one per wrapped line.

    Screen.concat
        [ Screen.text "This is a "
        , Screen.text "very important" |> Screen.bold
        , Screen.text " paragraph about decoding JSON values."
        ]
        |> Screen.wrapWidth 30
    -- Returns 3 Screens with "very important" still bold

Wraps at word boundaries (spaces). Words longer than `maxWidth` are broken
mid-word. Existing line breaks are preserved. Returns `[]` for empty screens
or non-positive widths.

-}
wrapWidth : Int -> Screen -> List Screen
wrapWidth maxWidth screen =
    if maxWidth <= 0 then
        []

    else
        flattenToSpanLines screen
            |> List.concatMap
                (\spanLine ->
                    if List.isEmpty spanLine then
                        [ blank ]

                    else
                        Internal.wrapSpans maxWidth spanLine
                            |> List.map (Internal.spansToScreen Internal.flatStyleToStyle)
                )
