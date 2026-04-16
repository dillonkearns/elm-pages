module Tui.Screen exposing
    ( Screen, text, styled, lines, concat, empty, blank
    , fg, bg, bold, dim, italic, underline, strikethrough, inverse, link
    , Style, plain, Attribute(..)
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

@docs Screen, text, styled, lines, concat, empty, blank


## Styling

Pipeline-style builders that compose on any `Screen` — text, concat, lines:

    Screen.text "warning" |> Screen.fg Ansi.Color.yellow |> Screen.bold

    Screen.concat [ a, b ] |> Screen.dim -- dims both a and b

@docs fg, bg, bold, dim, italic, underline, strikethrough, inverse, link

@docs Style, plain, Attribute


## Text Manipulation

@docs truncateWidth, wrapWidth


## Inspecting

@docs toString

For framework-level consumers that need to inspect rendered lines or rebuild
styled output, see [`Tui.Screen.Advanced`](Tui-Screen-Advanced).

-}

import Ansi.Color
import Tui.Screen.Internal as Internal



-- SCREEN


{-| Opaque type representing terminal output. Built from primitives, rendered by
the framework.
-}
type alias Screen =
    Internal.Screen Style


{-| Terminal cell style — foreground color, background color, text
attributes, and optional hyperlink. Matches the terminal cell model
(one fg, one bg, set of decoration flags, optional OSC 8 link).

    { fg = Just Ansi.Color.red
    , bg = Nothing
    , attributes = [ Screen.Bold, Screen.Underline ]
    , hyperlink = Nothing
    }

-}
type alias Style =
    { fg : Maybe Ansi.Color.Color
    , bg : Maybe Ansi.Color.Color
    , attributes : List Attribute
    , hyperlink : Maybe String
    }


{-| Default style — no colors, no decorations. Use record update to customize:

    import Tui.Screen as Screen exposing (plain)

    { plain | fg = Just Ansi.Color.cyan }
    { plain | attributes = [ Screen.Bold ] }

Note: Elm record update requires a bare identifier on the left side, so
import `plain` unqualified (as shown above) rather than writing
`{ Screen.plain | ... }` (which is a parse error).

-}
plain : Style
plain =
    { fg = Nothing
    , bg = Nothing
    , attributes = []
    , hyperlink = Nothing
    }


{-| A text decoration attribute.
-}
type Attribute
    = Bold
    | Dim
    | Italic
    | Underline
    | Strikethrough
    | Inverse


{-| Unstyled text.
-}
text : String -> Screen
text =
    Internal.ScreenText


{-| Styled text. Takes a [`Style`](#Style) record specifying foreground color,
background color, and text attributes.

    import Ansi.Color

    -- Bold red text
    Screen.styled { plain | fg = Just Ansi.Color.red, attributes = [ Screen.Bold ] } "error"

    -- Just bold, default colors
    Screen.styled { plain | attributes = [ Screen.Bold ] } "important"

    -- Foreground color only
    Screen.styled { plain | fg = Just Ansi.Color.cyan } "info"

-}
styled : Style -> String -> Screen
styled =
    Internal.ScreenStyled


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


{-| Empty screen — renders nothing, takes up zero lines. Use this as
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


{-| A blank line — renders one empty line. Useful as a vertical spacer
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
    Internal.applyStyle plain (\s -> { s | fg = Just color }) screen


{-| Set background color on a Screen.

    Screen.text "selected" |> Screen.bg Ansi.Color.blue

-}
bg : Ansi.Color.Color -> Screen -> Screen
bg color screen =
    Internal.applyStyle plain (\s -> { s | bg = Just color }) screen


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
    Internal.applyStyle plain (\s -> { s | hyperlink = Just url })


addAttr : Attribute -> Screen -> Screen
addAttr attr =
    Internal.applyStyle plain (\s -> { s | attributes = attr :: s.attributes })



-- STYLE CONVERSION (package-internal, used by span helpers)


styleToFlatStyle : Style -> Internal.FlatStyle
styleToFlatStyle s =
    let
        def : Internal.FlatStyle
        def =
            Internal.defaultFlatStyle

        base : Internal.FlatStyle
        base =
            { def
                | foreground = s.fg
                , background = s.bg
                , hyperlink = s.hyperlink
            }
    in
    List.foldl applyAttr base s.attributes


applyAttr : Attribute -> Internal.FlatStyle -> Internal.FlatStyle
applyAttr attr flatStyle =
    case attr of
        Bold ->
            { flatStyle | bold = True }

        Dim ->
            { flatStyle | dim = True }

        Italic ->
            { flatStyle | italic = True }

        Underline ->
            { flatStyle | underline = True }

        Strikethrough ->
            { flatStyle | strikethrough = True }

        Inverse ->
            { flatStyle | inverse = True }


flatStyleToAttrs : Internal.FlatStyle -> List Attribute
flatStyleToAttrs s =
    List.filterMap identity
        [ if s.bold then
            Just Bold

          else
            Nothing
        , if s.dim then
            Just Dim

          else
            Nothing
        , if s.italic then
            Just Italic

          else
            Nothing
        , if s.underline then
            Just Underline

          else
            Nothing
        , if s.strikethrough then
            Just Strikethrough

          else
            Nothing
        , if s.inverse then
            Just Inverse

          else
            Nothing
        ]


flattenToSpanLines : Screen -> List (List Internal.Span)
flattenToSpanLines =
    Internal.flattenToSpanLines styleToFlatStyle


flatStyleToStyle : Internal.FlatStyle -> Style
flatStyleToStyle fs =
    { fg = fs.foreground
    , bg = fs.background
    , attributes = flatStyleToAttrs fs
    , hyperlink = fs.hyperlink
    }



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
                                |> List.map (Internal.spanToScreen flatStyleToStyle)
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
                            |> List.map (Internal.spansToScreen flatStyleToStyle)
                )
