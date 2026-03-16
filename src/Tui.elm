module Tui exposing
    ( Screen, text, styled, lines, concat, empty
    , Style, plain
    , Attribute, bold, dim, italic, underline, strikethrough, inverse
    , Context
    , KeyEvent, Key(..), Direction(..), Modifier(..)
    , toString, toLines
    , encodeScreen
    )

{-| Core types for building terminal user interfaces.

`Tui.Screen` is the primitive view type — styled text with vertical and horizontal
composition. The framework handles rendering, diffing, and terminal management.

Colors use [`Ansi.Color.Color`](https://package.elm-lang.org/packages/wolfadex/elm-ansi/latest/Ansi-Color)
from the `wolfadex/elm-ansi` package:

    import Ansi.Color
    import Tui

    Tui.styled { Tui.plain | fg = Just Ansi.Color.red, attributes = [ Tui.bold ] } "error"

@docs Screen, text, styled, lines, concat, empty

@docs Style, plain

@docs Attribute, bold, dim, italic, underline, strikethrough, inverse

@docs Context

@docs KeyEvent, Key, Direction, Modifier

@docs toString, toLines

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
    Tui.styled { Tui.plain | fg = Just Ansi.Color.red, attributes = [ Tui.bold ] } "error"

    -- Just bold, default colors
    Tui.styled { Tui.plain | attributes = [ Tui.bold ] } "important"

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



-- STYLE


{-| Terminal cell style — foreground color, background color, and text
attributes. Matches the terminal cell model (one fg, one bg, set of decoration
flags).

    { fg = Just Ansi.Color.red
    , bg = Nothing
    , attributes = [ Tui.bold, Tui.underline ]
    }

-}
type alias Style =
    { fg : Maybe Ansi.Color.Color
    , bg : Maybe Ansi.Color.Color
    , attributes : List Attribute
    }


{-| Default style — no colors, no decorations. Use record update to customize:

    { Tui.plain | fg = Just Ansi.Color.cyan }
    { Tui.plain | attributes = [ Tui.bold ] }

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


{-| Bold text.
-}
bold : Attribute
bold =
    Bold


{-| Dim (faint) text.
-}
dim : Attribute
dim =
    Dim


{-| Italic text.
-}
italic : Attribute
italic =
    Italic


{-| Underlined text.
-}
underline : Attribute
underline =
    Underline


{-| Strikethrough text.
-}
strikethrough : Attribute
strikethrough =
    Strikethrough


{-| Inverse (swap foreground and background) text.
-}
inverse : Attribute
inverse =
    Inverse



-- CONTEXT


{-| Read-only terminal context provided to `view`.
-}
type alias Context =
    { width : Int
    , height : Int
    }



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



-- QUERYING


{-| Convert a Screen to a plain text string (no ANSI codes). Useful for testing
and debugging.
-}
toString : Screen -> String
toString screen =
    screen
        |> toLines
        |> String.join "\n"


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
            let
                flatStyle =
                    styleToFlatStyle stl
            in
            if String.isEmpty s then
                [ [] ]

            else
                s
                    |> String.split "\n"
                    |> List.map (\line -> [ { text = line, style = flatStyle } ])

        ScreenLines items ->
            List.concatMap flattenToSpanLines items

        ScreenConcat items ->
            let
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
