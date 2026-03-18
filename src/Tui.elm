module Tui exposing
    ( Screen, text, styled, lines, concat, empty, blank
    , fg, bg, bold, dim, italic, underline, strikethrough, inverse
    , Style, plain
    , Attribute(..)
    , Context, ColorProfile(..)
    , KeyEvent, Key(..), Direction(..), Modifier(..)
    , MouseEvent(..), MouseButton(..)
    , truncateWidth
    , toString, toLines, toScreenLines, lineCount
    , extractStyle
    , encodeScreen
    )

{-| Core types for building terminal user interfaces.

`Tui.Screen` is the primitive view type — styled text with vertical and horizontal
composition. The framework handles rendering, diffing, and terminal management.

Colors use [`Ansi.Color.Color`](https://package.elm-lang.org/packages/wolfadex/elm-ansi/latest/Ansi-Color)
from the `wolfadex/elm-ansi` package:

    import Ansi.Color
    import Tui

    Tui.styled { Tui.plain | fg = Just Ansi.Color.red, attributes = [ Tui.Bold ] } "error"

@docs Screen, text, styled, lines, concat, empty, blank

@docs fg, bg, bold, dim, italic, underline, strikethrough, inverse

@docs Style, plain

@docs Attribute

@docs Context, ColorProfile

@docs KeyEvent, Key, Direction, Modifier

@docs MouseEvent, MouseButton

@docs truncateWidth, toScreenLines, extractStyle

@docs toString, toLines, lineCount

@docs encodeScreen

-}

import Ansi.Color
import Json.Encode as Encode


{-| Opaque type representing terminal output. Built from primitives, rendered by
the framework.
-}
type Screen
    = ScreenText String
    | ScreenStyled Style String
    | ScreenLines (List Screen)
    | ScreenConcat (List Screen)
    | ScreenEmpty


{-| Unstyled text.
-}
text : String -> Screen
text =
    ScreenText


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
    ScreenStyled


{-| Stack screens vertically. Each item starts on a new line.
-}
lines : List Screen -> Screen
lines =
    ScreenLines


{-| Concatenate screens horizontally on the same line.
-}
concat : List Screen -> Screen
concat =
    ScreenConcat


{-| Empty screen — renders nothing.
-}
empty : Screen
empty =
    ScreenEmpty


{-| A blank line — alias for `text ""`. Useful as a spacer in `lines`.

    Tui.lines
        [ Tui.text "Title"
        , Tui.blank
        , Tui.text "Content"
        ]

-}
blank : Screen
blank =
    ScreenText ""



-- STYLE BUILDERS


{-| Set foreground color on a Screen. Composes with pipeline syntax:

    Tui.text "error" |> Tui.fg Ansi.Color.red
    Tui.text "warning" |> Tui.fg Ansi.Color.yellow |> Tui.bold

-}
fg : Ansi.Color.Color -> Screen -> Screen
fg color screen =
    applyStyle (\s -> { s | fg = Just color }) screen


{-| Set background color on a Screen.

    Tui.text "selected" |> Tui.bg Ansi.Color.blue

-}
bg : Ansi.Color.Color -> Screen -> Screen
bg color screen =
    applyStyle (\s -> { s | bg = Just color }) screen


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


{-| Apply a style transformation to a Screen. For ScreenText, wraps it in
ScreenStyled with the transformed plain style. For ScreenStyled, transforms
the existing style. For compound screens, wraps the whole thing.
-}
applyStyle : (Style -> Style) -> Screen -> Screen
applyStyle transform screen =
    case screen of
        ScreenText s ->
            ScreenStyled (transform plain) s

        ScreenStyled stl s ->
            ScreenStyled (transform stl) s

        _ ->
            -- For compound screens (Lines, Concat, Empty), wrap in a styled container
            -- This is a best-effort: the style applies to the outermost level
            screen


addAttr : Attribute -> Screen -> Screen
addAttr attr =
    applyStyle (\s -> { s | attributes = attr :: s.attributes })



-- STYLE RECORDS


{-| Terminal cell style — foreground color, background color, and text
attributes. Matches the terminal cell model (one fg, one bg, set of decoration
flags).

    { fg = Just Ansi.Color.red
    , bg = Nothing
    , attributes = [ Tui.Bold, Tui.Underline ]
    }

-}
type alias Style =
    { fg : Maybe Ansi.Color.Color
    , bg : Maybe Ansi.Color.Color
    , attributes : List Attribute
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
    }



-- ATTRIBUTES


{-| A text decoration attribute.
-}
type Attribute
    = Bold
    | Dim
    | Italic
    | Underline
    | Strikethrough
    | Inverse


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
`$NO_COLOR` → `$COLORTERM` → known terminals → `$TERM` suffix → default.

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



-- QUERYING


{-| Convert a Screen to a plain text string (no ANSI codes). Useful for testing
and debugging.
-}
toString : Screen -> String
toString screen =
    screen
        |> toLines
        |> String.join "\n"


{-| Split a Screen into a list of row Screens, preserving styles.
Unlike `toLines` (which returns `List String` and strips styles),
this returns `List Screen` with full styling information intact.

Useful for compositing: overlay a styled Screen on top of another
row-by-row, or render a snapshot in the test stepper with colors.

    rows = Tui.toScreenLines myScreen
    -- Each row is a styled Screen

-}
toScreenLines : Screen -> List Screen
toScreenLines screen =
    flattenToSpanLines screen
        |> List.map
            (\spans ->
                spans
                    |> List.map
                        (\span ->
                            ScreenStyled
                                { fg = span.style.foreground
                                , bg = span.style.background
                                , attributes = flatStyleToAttrs span.style
                                }
                                span.text
                        )
                    |> ScreenConcat
            )


{-| Extract the outermost style from a Screen. Returns `plain` for unstyled
text. Useful for extending a row's style to fill remaining width (e.g.,
making a selection highlight span the full pane width).

    style = Tui.extractStyle selectedLine
    padding = Tui.styled style (String.repeat n " ")

-}
extractStyle : Screen -> Style
extractStyle screen =
    case screen of
        ScreenStyled stl _ ->
            stl

        ScreenConcat items ->
            case items of
                (ScreenStyled stl _) :: _ ->
                    stl

                _ ->
                    plain

        _ ->
            plain


{-| Truncate a Screen to a maximum width in columns, preserving styles.
Adds "…" if truncated. Works on the first line only (for single-line content).
-}
truncateWidth : Int -> Screen -> Screen
truncateWidth maxWidth screen =
    let
        spans : List Span
        spans =
            case flattenToSpanLines screen of
                first :: _ ->
                    first

                [] ->
                    []

        truncated : List Span
        truncated =
            truncateSpans maxWidth spans
    in
    case truncated of
        [] ->
            empty

        _ ->
            truncated
                |> List.map
                    (\span ->
                        ScreenStyled
                            { fg = span.style.foreground
                            , bg = span.style.background
                            , attributes = flatStyleToAttrs span.style
                            }
                            span.text
                    )
                |> ScreenConcat


truncateSpans : Int -> List Span -> List Span
truncateSpans remaining spans =
    -- elm-review: known-unoptimized-recursion
    case spans of
        [] ->
            []

        span :: rest ->
            if remaining <= 0 then
                []

            else
                let
                    spanLen : Int
                    spanLen =
                        String.length span.text
                in
                if spanLen <= remaining then
                    span :: truncateSpans (remaining - spanLen) rest

                else if remaining <= 1 then
                    [ { span | text = "…" } ]

                else
                    [ { span | text = String.left (remaining - 1) span.text ++ "…" } ]


flatStyleToAttrs : FlatStyle -> List Attribute
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


{-| Get the number of lines in a Screen. Useful for layout calculations.
-}
lineCount : Screen -> Int
lineCount screen =
    flattenToSpanLines screen |> List.length


{-| Convert a Screen to a list of plain text lines. Useful for testing.
-}
toLines : Screen -> List String
toLines screen =
    flattenToSpanLines screen
        |> List.map (\spans -> spans |> List.map .text |> String.concat)



-- INTERNAL: FLATTENING


type alias Span =
    { text : String
    , style : FlatStyle
    }


type alias FlatStyle =
    { bold : Bool
    , dim : Bool
    , italic : Bool
    , underline : Bool
    , strikethrough : Bool
    , inverse : Bool
    , foreground : Maybe Ansi.Color.Color
    , background : Maybe Ansi.Color.Color
    }


defaultFlatStyle : FlatStyle
defaultFlatStyle =
    { bold = False
    , dim = False
    , italic = False
    , underline = False
    , strikethrough = False
    , inverse = False
    , foreground = Nothing
    , background = Nothing
    }


styleToFlatStyle : Style -> FlatStyle
styleToFlatStyle s =
    let
        base : FlatStyle
        base =
            { defaultFlatStyle
                | foreground = s.fg
                , background = s.bg
            }
    in
    List.foldl applyAttr base s.attributes


applyAttr : Attribute -> FlatStyle -> FlatStyle
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


{-| Flatten a Screen tree into a list of lines, where each line is a list of
styled spans.
-}
flattenToSpanLines : Screen -> List (List Span)
flattenToSpanLines screen =
    -- elm-review: known-unoptimized-recursion
    case screen of
        ScreenEmpty ->
            []

        ScreenText s ->
            if String.isEmpty s then
                [ [] ]

            else
                s
                    |> String.split "\n"
                    |> List.map (\line -> [ { text = line, style = defaultFlatStyle } ])

        ScreenStyled stl s ->
            if String.isEmpty s then
                [ [] ]

            else
                let
                    flatStyle : FlatStyle
                    flatStyle =
                        styleToFlatStyle stl
                in
                s
                    |> String.split "\n"
                    |> List.map (\line -> [ { text = line, style = flatStyle } ])

        ScreenLines items ->
            List.concatMap flattenToSpanLines items

        ScreenConcat items ->
            let
                allFirstLineSpans : List Span
                allFirstLineSpans =
                    items
                        |> List.concatMap
                            (\item ->
                                case flattenToSpanLines item of
                                    [] ->
                                        []

                                    first :: _ ->
                                        first
                            )
            in
            [ allFirstLineSpans ]



-- ENCODING (for sending to JS runtime)


{-| Encode a Screen as JSON for the JS rendering pipeline.
-}
encodeScreen : Screen -> Encode.Value
encodeScreen screen =
    flattenToSpanLines screen
        |> Encode.list
            (\spanLine ->
                Encode.list encodeSpan spanLine
            )


encodeSpan : Span -> Encode.Value
encodeSpan span =
    Encode.object
        [ ( "text", Encode.string span.text )
        , ( "style", encodeFlatStyle span.style )
        ]


encodeFlatStyle : FlatStyle -> Encode.Value
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
