module Tui.Screen exposing
    ( Screen, text, styled, lines, concat, empty, blank
    , fg, bg, bold, dim, italic, underline, strikethrough, inverse, link
    , Style, plain, extractStyle
    , Attribute(..)
    , truncateWidth, wrapWidth
    , toString, encodeScreen
    , Span
    , toSpanLines, fromSpans
    , truncateSpans, wrapSpans
    )

{-| Styled terminal output — the thing a TUI's `view` returns.

A `Screen` is an opaque tree of styled text primitives. Build one from
[`text`](#text), style it with pipeline builders, compose with
[`lines`](#lines) and [`concat`](#concat), and return it from your `view`
function. The framework handles rendering and cell-level diffing.

    import Tui.Screen as Screen exposing (plain)

    view : Tui.Context -> Model -> Screen.Screen
    view ctx model =
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
    Screen.concat [ a, b ] |> Screen.dim  -- dims both a and b

@docs fg, bg, bold, dim, italic, underline, strikethrough, inverse, link

@docs Style, plain, extractStyle, Attribute


## Text Manipulation

@docs truncateWidth, wrapWidth


## Inspecting

@docs toString, encodeScreen


## Advanced: styled span views

A styled-span view of a [`Screen`](#Screen). Most apps do not need this
directly — it is useful when analyzing or rebuilding styled terminal
content while preserving colors, text attributes, and hyperlinks.

@docs Span
@docs toSpanLines, fromSpans
@docs truncateSpans, wrapSpans

-}

import Ansi.Color
import Json.Encode as Encode
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
        Just err -> Screen.text err |> Screen.fg Ansi.Color.red
        Nothing -> Screen.empty

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



-- STYLE CONVERSION (package-internal, used by encodeScreen and span helpers)


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


flatStyleToStyle : Internal.FlatStyle -> Style
flatStyleToStyle fs =
    { fg = fs.foreground
    , bg = fs.background
    , attributes = flatStyleToAttrs fs
    , hyperlink = fs.hyperlink
    }


flattenToSpanLines : Screen -> List (List Internal.Span)
flattenToSpanLines =
    Internal.flattenToSpanLines styleToFlatStyle


spanToInternal : Span -> Internal.Span
spanToInternal span =
    { text = span.text
    , style = styleToFlatStyle span.style
    }


spanFromInternal : Internal.Span -> Span
spanFromInternal span =
    { text = span.text
    , style = flatStyleToStyle span.style
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


{-| Extract the outermost style from a Screen. Returns `plain` for unstyled
text. Useful for extending a row's style to fill remaining width (e.g.,
making a selection highlight span the full pane width).

    style = Screen.extractStyle selectedLine
    padding = Screen.styled style (String.repeat n " ")

-}
extractStyle : Screen -> Style
extractStyle =
    Internal.extractStyle plain


{-| Truncate a Screen to a maximum width in columns, preserving styles.
Adds "\u{2026}" if truncated. Works on the first line only. Returns `empty`
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


{-| Serialize a Screen to JSON. Used internally by the TUI runtime to send
rendered output to the Node side, and exposed here so tests and tooling can
assert on the exact wire format. Most apps do not need this.
-}
encodeScreen : Screen -> Encode.Value
encodeScreen screen =
    flattenToSpanLines screen
        |> Encode.list (\spanLine -> Encode.list encodeSpanJson spanLine)


encodeSpanJson : Internal.Span -> Encode.Value
encodeSpanJson span =
    Encode.object
        [ ( "text", Encode.string span.text )
        , ( "style", encodeFlatStyle span.style )
        ]


encodeFlatStyle : Internal.FlatStyle -> Encode.Value
encodeFlatStyle flatStyle =
    Encode.object
        (List.filterMap identity
            [ if flatStyle.bold then
                Just ( "bold", Encode.bool True )

              else
                Nothing
            , if flatStyle.dim then
                Just ( "dim", Encode.bool True )

              else
                Nothing
            , if flatStyle.italic then
                Just ( "italic", Encode.bool True )

              else
                Nothing
            , if flatStyle.underline then
                Just ( "underline", Encode.bool True )

              else
                Nothing
            , if flatStyle.strikethrough then
                Just ( "strikethrough", Encode.bool True )

              else
                Nothing
            , if flatStyle.inverse then
                Just ( "inverse", Encode.bool True )

              else
                Nothing
            , flatStyle.foreground |> Maybe.map (\c -> ( "foreground", encodeColor c ))
            , flatStyle.background |> Maybe.map (\c -> ( "background", encodeColor c ))
            , flatStyle.hyperlink |> Maybe.map (\url -> ( "hyperlink", Encode.string url ))
            ]
        )


encodeColor : Ansi.Color.Color -> Encode.Value
encodeColor ansiColor =
    case ansiColor of
        Ansi.Color.Black ->
            Encode.string "black"

        Ansi.Color.Red ->
            Encode.string "red"

        Ansi.Color.Green ->
            Encode.string "green"

        Ansi.Color.Yellow ->
            Encode.string "yellow"

        Ansi.Color.Blue ->
            Encode.string "blue"

        Ansi.Color.Magenta ->
            Encode.string "magenta"

        Ansi.Color.Cyan ->
            Encode.string "cyan"

        Ansi.Color.White ->
            Encode.string "white"

        Ansi.Color.BrightBlack ->
            Encode.string "brightBlack"

        Ansi.Color.BrightRed ->
            Encode.string "brightRed"

        Ansi.Color.BrightGreen ->
            Encode.string "brightGreen"

        Ansi.Color.BrightYellow ->
            Encode.string "brightYellow"

        Ansi.Color.BrightBlue ->
            Encode.string "brightBlue"

        Ansi.Color.BrightMagenta ->
            Encode.string "brightMagenta"

        Ansi.Color.BrightCyan ->
            Encode.string "brightCyan"

        Ansi.Color.BrightWhite ->
            Encode.string "brightWhite"

        Ansi.Color.Custom256 { color } ->
            Encode.object [ ( "color256", Encode.int color ) ]

        Ansi.Color.CustomTrueColor { red, green, blue } ->
            Encode.object
                [ ( "r", Encode.int red )
                , ( "g", Encode.int green )
                , ( "b", Encode.int blue )
                ]



-- STYLED SPAN VIEW (advanced)


{-| A styled text segment from a rendered screen line.
-}
type alias Span =
    { text : String
    , style : Style
    }


{-| Flatten a `Screen` into styled span lines.
-}
toSpanLines : Screen -> List (List Span)
toSpanLines screen =
    flattenToSpanLines screen
        |> List.map (List.map spanFromInternal)


{-| Rebuild a `Screen` from styled spans.
-}
fromSpans : List Span -> Screen
fromSpans spans =
    spans
        |> List.map spanToInternal
        |> Internal.spansToScreen flatStyleToStyle


{-| Truncate a span line to a maximum width, preserving styles.
-}
truncateSpans : Int -> List Span -> List Span
truncateSpans maxWidth spans =
    spans
        |> List.map spanToInternal
        |> Internal.truncateSpans maxWidth
        |> List.map spanFromInternal


{-| Wrap a span line to a maximum width, preserving styles.
-}
wrapSpans : Int -> List Span -> List (List Span)
wrapSpans maxWidth spans =
    spans
        |> List.map spanToInternal
        |> Internal.wrapSpans maxWidth
        |> List.map (List.map spanFromInternal)
