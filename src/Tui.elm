module Tui exposing
    ( Screen, text, styled, lines, concat, empty
    , Attribute, bold, dim, italic, underline, strikethrough, inverse
    , foreground, background
    , Color, black, red, green, yellow, blue, magenta, cyan, white, rgb
    , Context
    , KeyEvent, Key(..), Direction(..), Modifier(..)
    , toString, toLines
    , encodeScreen
    )

{-| Core types for building terminal user interfaces.

`Tui.Screen` is the primitive view type — styled text with vertical and horizontal
composition. The framework handles rendering, diffing, and terminal management.

For layout (row/column/fill/border), use a layout package built on top of these
primitives.

@docs Screen, text, styled, lines, concat, empty

@docs Attribute, bold, dim, italic, underline, strikethrough, inverse
@docs foreground, background

@docs Color, black, red, green, yellow, blue, magenta, cyan, white, rgb

@docs Context

@docs KeyEvent, Key, Direction, Modifier

@docs toString, toLines

@docs encodeScreen

-}

import Json.Encode as Encode


{-| Opaque type representing terminal output. Built from primitives, rendered by
the framework.
-}
type Screen
    = ScreenText String
    | ScreenStyled (List Attribute) String
    | ScreenLines (List Screen)
    | ScreenConcat (List Screen)
    | ScreenEmpty


{-| Unstyled text.
-}
text : String -> Screen
text =
    ScreenText


{-| Styled text.

    Tui.styled [ Tui.bold, Tui.foreground Tui.cyan ] "Hello"

-}
styled : List Attribute -> String -> Screen
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



-- ATTRIBUTES


{-| A styling attribute for text.
-}
type Attribute
    = Bold
    | Dim
    | Italic
    | Underline
    | Strikethrough
    | Inverse
    | Foreground Color
    | Background Color


bold : Attribute
bold =
    Bold


dim : Attribute
dim =
    Dim


italic : Attribute
italic =
    Italic


underline : Attribute
underline =
    Underline


strikethrough : Attribute
strikethrough =
    Strikethrough


inverse : Attribute
inverse =
    Inverse


foreground : Color -> Attribute
foreground =
    Foreground


background : Color -> Attribute
background =
    Background



-- COLORS


{-| Terminal color.
-}
type Color
    = Ansi16 AnsiColor
    | Rgb255 Int Int Int


type AnsiColor
    = Black
    | Red
    | Green
    | Yellow
    | Blue
    | Magenta
    | Cyan
    | White


black : Color
black =
    Ansi16 Black


red : Color
red =
    Ansi16 Red


green : Color
green =
    Ansi16 Green


yellow : Color
yellow =
    Ansi16 Yellow


blue : Color
blue =
    Ansi16 Blue


magenta : Color
magenta =
    Ansi16 Magenta


cyan : Color
cyan =
    Ansi16 Cyan


white : Color
white =
    Ansi16 White


{-| Truecolor (24-bit). The framework auto-downgrades on terminals that don't
support it.
-}
rgb : Int -> Int -> Int -> Color
rgb =
    Rgb255



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
    , style : Style
    }


type alias Style =
    { bold : Bool
    , dim : Bool
    , italic : Bool
    , underline : Bool
    , strikethrough : Bool
    , inverse : Bool
    , foreground : Maybe Color
    , background : Maybe Color
    }


defaultStyle : Style
defaultStyle =
    { bold = False
    , dim = False
    , italic = False
    , underline = False
    , strikethrough = False
    , inverse = False
    , foreground = Nothing
    , background = Nothing
    }


attrsToStyle : List Attribute -> Style
attrsToStyle attrs =
    List.foldl applyAttr defaultStyle attrs


applyAttr : Attribute -> Style -> Style
applyAttr attr style =
    case attr of
        Bold ->
            { style | bold = True }

        Dim ->
            { style | dim = True }

        Italic ->
            { style | italic = True }

        Underline ->
            { style | underline = True }

        Strikethrough ->
            { style | strikethrough = True }

        Inverse ->
            { style | inverse = True }

        Foreground c ->
            { style | foreground = Just c }

        Background c ->
            { style | background = Just c }


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
                    |> List.map (\line -> [ { text = line, style = defaultStyle } ])

        ScreenStyled attrs s ->
            let
                style =
                    attrsToStyle attrs
            in
            if String.isEmpty s then
                [ [] ]

            else
                s
                    |> String.split "\n"
                    |> List.map (\line -> [ { text = line, style = style } ])

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
        , ( "style", encodeStyle span.style )
        ]


encodeStyle : Style -> Encode.Value
encodeStyle style =
    Encode.object
        (List.filterMap identity
            [ if style.bold then
                Just ( "bold", Encode.bool True )

              else
                Nothing
            , if style.dim then
                Just ( "dim", Encode.bool True )

              else
                Nothing
            , if style.italic then
                Just ( "italic", Encode.bool True )

              else
                Nothing
            , if style.underline then
                Just ( "underline", Encode.bool True )

              else
                Nothing
            , if style.strikethrough then
                Just ( "strikethrough", Encode.bool True )

              else
                Nothing
            , if style.inverse then
                Just ( "inverse", Encode.bool True )

              else
                Nothing
            , style.foreground |> Maybe.map (\c -> ( "foreground", encodeColor c ))
            , style.background |> Maybe.map (\c -> ( "background", encodeColor c ))
            ]
        )


encodeColor : Color -> Encode.Value
encodeColor color =
    case color of
        Ansi16 ansiColor ->
            Encode.string (ansiColorName ansiColor)

        Rgb255 r g b ->
            Encode.object
                [ ( "r", Encode.int r )
                , ( "g", Encode.int g )
                , ( "b", Encode.int b )
                ]


ansiColorName : AnsiColor -> String
ansiColorName color =
    case color of
        Black ->
            "black"

        Red ->
            "red"

        Green ->
            "green"

        Yellow ->
            "yellow"

        Blue ->
            "blue"

        Magenta ->
            "magenta"

        Cyan ->
            "cyan"

        White ->
            "white"
