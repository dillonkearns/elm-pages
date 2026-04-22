module Tui.Screen.Internal.Encode exposing (screen)

import Ansi.Color
import Json.Encode as Encode
import Tui.Screen
import Tui.Screen.Internal as Internal


screen : Tui.Screen.Screen -> Encode.Value
screen tuiScreen =
    Internal.flattenToSpanLines styleToFlatStyle tuiScreen
        |> Encode.list (\spanLine -> Encode.list encodeSpan spanLine)


encodeSpan : Internal.Span -> Encode.Value
encodeSpan span =
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


styleToFlatStyle : Tui.Screen.Style -> Internal.FlatStyle
styleToFlatStyle =
    Internal.styleToFlatStyle
