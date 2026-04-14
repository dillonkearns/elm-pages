module Tui exposing
    ( Screen, text, styled, lines, concat, empty, blank
    , fg, bg, bold, dim, italic, underline, strikethrough, inverse, link
    , Style, plain, extractStyle
    , Attribute(..)
    , Context, ColorProfile(..)
    , KeyEvent, Key(..), Direction(..), Modifier(..)
    , MouseEvent(..), MouseButton(..)
    , truncateWidth, wrapWidth
    , toString
    )

{-| Build terminal user interfaces with styled text, keyboard/mouse events,
and composable screens.

Use [`Pages.Script.tui`](Pages-Script#tui) to wire up a TUI as an elm-pages
script with `init`, `update`, `view`, and `subscriptions`. This module provides
the types you'll use in `view` (returning a `Screen`) and `subscriptions`
(receiving `KeyEvent`, `MouseEvent`).

A minimal TUI view:

    view : Tui.Context -> Model -> Tui.Screen
    view ctx model =
        Tui.lines
            [ Tui.text "Hello, TUI!" |> Tui.bold
            , Tui.blank
            , Tui.text ("Count: " ++ String.fromInt model.count)
                |> Tui.fg Ansi.Color.cyan
            ]


## Building Screens

Screens compose vertically with [`lines`](#lines) and horizontally with
[`concat`](#concat). For split-pane layouts, see the `Tui.Layout` module in
the `tui-widgets` package.

@docs Screen, text, styled, lines, concat, empty, blank


## Styling

Pipeline-style builders that compose on any `Screen` — text, concat, lines:

    Tui.text "warning" |> Tui.fg Ansi.Color.yellow |> Tui.bold
    Tui.concat [ a, b ] |> Tui.dim  -- dims both a and b

@docs fg, bg, bold, dim, italic, underline, strikethrough, inverse, link

@docs Style, plain, extractStyle, Attribute


## Terminal Context

Passed to your `view` function. Use `colorProfile` to adapt themes for
different terminal capabilities.

@docs Context, ColorProfile


## Events

Subscribe to events via `Tui.Sub`. Your `subscriptions` function
declares which events to listen for, and they arrive as these types in your
`update`:

    subscriptions model =
        Tui.Sub.batch
            [ Tui.Sub.onKeyPress KeyPressed
            , Tui.Sub.onMouse MouseEvent
            ]

@docs KeyEvent, Key, Direction, Modifier

@docs MouseEvent, MouseButton


## Text Manipulation

@docs truncateWidth, wrapWidth


## Inspecting

@docs toString

-}

import Ansi.Color
import Tui.Screen.Internal as Internal


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
    , attributes = [ Tui.Bold, Tui.Underline ]
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

    { Tui.plain | fg = Just Ansi.Color.cyan }
    { Tui.plain | attributes = [ Tui.Bold ] }

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
    Tui.styled { Tui.plain | fg = Just Ansi.Color.red, attributes = [ Tui.Bold ] } "error"

    -- Just bold, default colors
    Tui.styled { Tui.plain | attributes = [ Tui.Bold ] } "important"

    -- Foreground color only
    Tui.styled { Tui.plain | fg = Just Ansi.Color.cyan } "info"

-}
styled : Style -> String -> Screen
styled =
    Internal.ScreenStyled


{-| Stack screens vertically. Each item starts on a new line.
-}
lines : List Screen -> Screen
lines =
    Internal.ScreenLines


{-| Concatenate screens horizontally on the same line.
-}
concat : List Screen -> Screen
concat =
    Internal.ScreenConcat


{-| Empty screen — renders nothing, takes up zero lines. Use this as
a "null" value, for example with `Maybe.withDefault`:

    case maybeError of
        Just err -> Tui.text err |> Tui.fg Ansi.Color.red
        Nothing -> Tui.empty

Note: this is different from [`blank`](#blank) which renders one empty line.
`empty` produces no output at all.

-}
empty : Screen
empty =
    Internal.ScreenEmpty


{-| A blank line — renders one empty line. Useful as a vertical spacer
in [`lines`](#lines):

    Tui.lines
        [ Tui.text "Title"
        , Tui.blank
        , Tui.text "Content"
        ]

Note: this is different from [`empty`](#empty) which renders nothing.
`blank` produces a visible gap (one empty row).

-}
blank : Screen
blank =
    Internal.ScreenText ""



-- STYLE BUILDERS


{-| Set foreground color on a Screen. Composes with pipeline syntax:

    Tui.text "error" |> Tui.fg Ansi.Color.red
    Tui.text "warning" |> Tui.fg Ansi.Color.yellow |> Tui.bold

-}
fg : Ansi.Color.Color -> Screen -> Screen
fg color screen =
    Internal.applyStyle plain (\s -> { s | fg = Just color }) screen


{-| Set background color on a Screen.

    Tui.text "selected" |> Tui.bg Ansi.Color.blue

-}
bg : Ansi.Color.Color -> Screen -> Screen
bg color screen =
    Internal.applyStyle plain (\s -> { s | bg = Just color }) screen


{-| Apply bold attribute.

    Tui.text "important" |> Tui.bold

-}
bold : Screen -> Screen
bold =
    addAttr Bold


{-| Apply dim attribute.

    Tui.text "muted" |> Tui.dim

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

    Tui.text "elm/core"
        |> Tui.underline
        |> Tui.fg Ansi.Color.blue
        |> Tui.link { url = "https://package.elm-lang.org/packages/elm/core/latest" }

-}
link : { url : String } -> Screen -> Screen
link { url } =
    Internal.applyStyle plain (\s -> { s | hyperlink = Just url })


addAttr : Attribute -> Screen -> Screen
addAttr attr =
    Internal.applyStyle plain (\s -> { s | attributes = attr :: s.attributes })



-- STYLE CONVERSION


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


spanToScreen : Internal.Span -> Screen
spanToScreen =
    Internal.spanToScreen flatStyleToStyle


spansToScreen : List Internal.Span -> Screen
spansToScreen =
    Internal.spansToScreen flatStyleToStyle



-- CONTEXT


{-| Read-only terminal context provided to `view`.
-}
type alias Context =
    { width : Int
    , height : Int
    , colorProfile : ColorProfile
    }


{-| Terminal color capability, detected at init from environment variables.
Follows charmbracelet/colorprofile's detection precedence:
`$NO_COLOR` -> `$COLORTERM` -> known terminals -> `$TERM` suffix -> default.

The renderer automatically degrades colors based on the profile — the Elm app
can always use the highest fidelity colors and they'll be converted. But this
field lets apps adapt themes (e.g., use different palettes for 16-color).

    view ctx model =
        case ctx.colorProfile of
            Tui.TrueColor -> richColorView model
            _ -> basicColorView model

-}
type ColorProfile
    = TrueColor
    | Color256
    | Color16
    | Mono



-- EVENTS


{-| A keyboard event from the terminal.
-}
type alias KeyEvent =
    { key : Key
    , modifiers : List Modifier
    }


{-| Key values.
-}
type Key
    = Character Char
    | Enter
    | Escape
    | Tab
    | Backspace
    | Delete
    | Arrow Direction
    | FunctionKey Int
    | Home
    | End
    | PageUp
    | PageDown


{-| Arrow key direction.
-}
type Direction
    = Up
    | Down
    | Left
    | Right


{-| Key modifier.
-}
type Modifier
    = Ctrl
    | Alt
    | Shift


{-| Mouse event from the terminal. Uses SGR extended mouse mode for accurate
coordinates on any terminal size.

Coordinates are 0-based: `{ row = 0, col = 0 }` is the top-left corner.

`amount` on scroll events is the number of coalesced scroll steps. Rapid
scrolling batches events on the JS side (like gocui's event drain) so you
get one event with `amount = 5` instead of 5 separate events. Multiply your
scroll distance by `amount` for responsive feel.

-}
type MouseEvent
    = Click { row : Int, col : Int, button : MouseButton }
    | ScrollUp { row : Int, col : Int, amount : Int }
    | ScrollDown { row : Int, col : Int, amount : Int }


{-| Mouse button for click events.
-}
type MouseButton
    = LeftButton
    | MiddleButton
    | RightButton



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

    style = Tui.extractStyle selectedLine
    padding = Tui.styled style (String.repeat n " ")

-}
extractStyle : Screen -> Style
extractStyle =
    Internal.extractStyle plain


{-| Truncate a Screen to a maximum width in columns, preserving styles.
Adds "\u{2026}" if truncated. Works on the first line only (for single-line content).
-}
truncateWidth : Int -> Screen -> Screen
truncateWidth maxWidth screen =
    let
        spans : List Internal.Span
        spans =
            case flattenToSpanLines screen of
                first :: _ ->
                    first

                [] ->
                    []

        truncated : List Internal.Span
        truncated =
            Internal.truncateSpans maxWidth spans
    in
    case truncated of
        [] ->
            empty

        _ ->
            truncated
                |> List.map spanToScreen
                |> Internal.ScreenConcat


{-| Wrap a Screen to a maximum width, preserving styles across line breaks.
Returns a list of Screens, one per wrapped line.

    Tui.concat
        [ Tui.text "This is a "
        , Tui.text "very important" |> Tui.bold
        , Tui.text " paragraph about decoding JSON values."
        ]
        |> Tui.wrapWidth 30
    -- Returns 3 Screens with "very important" still bold

Wraps at word boundaries (spaces). Words longer than `maxWidth` are broken
mid-word. Returns `[]` for empty screens.

-}
wrapWidth : Int -> Screen -> List Screen
wrapWidth maxWidth screen =
    let
        spans : List Internal.Span
        spans =
            case flattenToSpanLines screen of
                first :: _ ->
                    first

                [] ->
                    []
    in
    if List.isEmpty spans then
        []

    else
        Internal.wrapSpans maxWidth spans
            |> List.map spansToScreen
