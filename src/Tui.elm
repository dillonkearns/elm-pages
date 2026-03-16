module Tui exposing
    ( Screen, text, styled, lines, concat, empty
    , Attribute, bold, dim, italic, underline, strikethrough, inverse
    , foreground, background
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

Colors use [`Ansi.Color.Color`](https://package.elm-lang.org/packages/wolfadex/elm-ansi/latest/Ansi-Color)
from the `wolfadex/elm-ansi` package. This gives you standard ANSI colors,
bright variants, 256-color, and truecolor out of the box:

    import Ansi.Color
    import Tui

    Tui.styled [ Tui.foreground Ansi.Color.cyan ] "info"
    Tui.styled [ Tui.foreground Ansi.Color.brightRed ] "error"
    Tui.styled [ Tui.foreground (Ansi.Color.rgb { red = 255, green = 128, blue = 0 }) ] "orange"

@docs Screen, text, styled, lines, concat, empty

@docs Attribute, bold, dim, italic, underline, strikethrough, inverse
@docs foreground, background

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

    import Ansi.Color

    Tui.styled [ Tui.bold, Tui.foreground Ansi.Color.cyan ] "Hello"

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


{-| A styling attribute for text. Matches the terminal cell model: foreground
color, background color, and text decoration flags.
-}
type Attribute
    = Bold
    | Dim
    | Italic
    | Underline
    | Strikethrough
    | Inverse
    | Foreground Ansi.Color.Color
    | Background Ansi.Color.Color


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


{-| Set the text foreground color.

    import Ansi.Color

    Tui.styled [ Tui.foreground Ansi.Color.red ] "error"
    Tui.styled [ Tui.foreground (Ansi.Color.rgb { red = 255, green = 128, blue = 0 }) ] "orange"

-}
foreground : Ansi.Color.Color -> Attribute
foreground =
    Foreground


{-| Set the text background color.

    import Ansi.Color

    Tui.styled [ Tui.background Ansi.Color.blue ] "highlighted"

-}
background : Ansi.Color.Color -> Attribute
background =
    Background



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
    , foreground : Maybe Ansi.Color.Color
    , background : Maybe Ansi.Color.Color
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
