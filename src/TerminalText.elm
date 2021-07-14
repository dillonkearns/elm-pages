module TerminalText exposing
    ( Text(..)
    , ansi
    , ansiPrefix
    , blue
    , colorToString
    , cyan
    , encoder
    , fromAnsiString
    , getString
    , green
    , red
    , resetColors
    , text
    , toString
    , toString_
    , yellow
    )

import Ansi
import Json.Encode as Encode


type Text
    = RawText String
    | Style Ansi.Color Text


text : String -> Text
text value =
    RawText value


cyan : Text -> Text
cyan inner =
    Style Ansi.Cyan inner


green : Text -> Text
green inner =
    Style Ansi.Green inner


yellow : Text -> Text
yellow inner =
    Style Ansi.Yellow inner


red : Text -> Text
red inner =
    Style Ansi.Red inner


blue : Text -> Text
blue inner =
    Style Ansi.Blue inner


resetColors : String
resetColors =
    ansi "[0m"


ansi : String -> String
ansi code =
    ansiPrefix ++ code


ansiPrefix : String
ansiPrefix =
    "\u{001B}"


colorToString : Ansi.Color -> String
colorToString color =
    ansi <|
        case color of
            Ansi.Red ->
                "[31m"

            Ansi.Blue ->
                "[34m"

            Ansi.Green ->
                "[32m"

            Ansi.Yellow ->
                "[33m"

            Ansi.Cyan ->
                "[36m"

            _ ->
                -- TODO
                ""


toString : List Text -> String
toString list =
    list
        |> List.map toString_
        |> String.join ""


toString_ : Text -> String
toString_ textValue =
    -- elm-review: known-unoptimized-recursion
    case textValue of
        RawText content ->
            content

        Style color innerText ->
            String.concat
                [ colorToString color
                , toString_ innerText
                , resetColors
                ]


fromAnsiString : String -> List Text
fromAnsiString ansiString =
    Ansi.parseInto ( Nothing, [] ) parseInto ansiString
        |> Tuple.second
        |> List.reverse


parseInto : Ansi.Action -> ( Maybe Ansi.Color, List Text ) -> ( Maybe Ansi.Color, List Text )
parseInto action ( pendingStyle, soFar ) =
    case action of
        Ansi.Print string ->
            case pendingStyle of
                Just pendingColor ->
                    ( Nothing, Style pendingColor (RawText string) :: soFar )

                Nothing ->
                    ( Nothing, RawText string :: soFar )

        Ansi.Remainder string ->
            ( pendingStyle, soFar )

        Ansi.SetForeground maybeColor ->
            case maybeColor of
                Just newColor ->
                    ( Just newColor, soFar )

                Nothing ->
                    ( Nothing, soFar )

        Ansi.SetBold bool ->
            ( pendingStyle, soFar )

        Ansi.SetFaint bool ->
            ( pendingStyle, soFar )

        Ansi.SetItalic bool ->
            ( pendingStyle, soFar )

        Ansi.SetUnderline bool ->
            ( pendingStyle, soFar )

        Ansi.SetBackground maybeColor ->
            ( pendingStyle, soFar )

        _ ->
            ( pendingStyle, soFar )


encoder : Text -> Encode.Value
encoder node =
    Encode.object
        [ ( "bold", Encode.bool False )
        , ( "underline", Encode.bool False )
        , ( "color"
          , Encode.string <|
                case node of
                    RawText _ ->
                        "WHITE"

                    Style color _ ->
                        case color of
                            Ansi.Red ->
                                "red"

                            Ansi.Blue ->
                                "blue"

                            Ansi.Green ->
                                "green"

                            Ansi.Yellow ->
                                "yellow"

                            Ansi.Cyan ->
                                "cyan"

                            Ansi.Black ->
                                "black"

                            Ansi.Magenta ->
                                "magenta"

                            Ansi.White ->
                                "white"

                            Ansi.BrightBlack ->
                                "BLACK"

                            Ansi.BrightRed ->
                                "RED"

                            Ansi.BrightGreen ->
                                "GREEN"

                            Ansi.BrightYellow ->
                                "YELLOW"

                            Ansi.BrightBlue ->
                                "BLUE"

                            Ansi.BrightMagenta ->
                                "MAGENTA"

                            Ansi.BrightCyan ->
                                "CYAN"

                            Ansi.BrightWhite ->
                                "WHITE"

                            Ansi.Custom _ _ _ ->
                                "NOTHANDLED"
          )
        , ( "string", Encode.string (getString node) )
        ]


getString : Text -> String
getString node =
    case node of
        RawText string ->
            string

        Style _ innerNode ->
            getString innerNode
