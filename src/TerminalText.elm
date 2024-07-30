module TerminalText exposing
    ( Text(..)
    , ansi
    , ansiPrefix
    , blue
    , colorToString
    , cyan
    , encoder
    , fromAnsiString
    , green
    , red
    , resetColors
    , text
    , toPlainString
    , toString
    , toString_
    , yellow
    )

import Ansi.Color
import Ansi.Parser
import Json.Encode as Encode


type Text
    = Style AnsiStyle String


text : String -> Text
text value =
    Style blankStyle value


cyan : String -> Text
cyan inner =
    Style { blankStyle | color = Just Ansi.Color.Cyan } inner


green : String -> Text
green inner =
    Style { blankStyle | color = Just Ansi.Color.Green } inner


yellow : String -> Text
yellow inner =
    Style { blankStyle | color = Just Ansi.Color.Yellow } inner


red : String -> Text
red inner =
    Style { blankStyle | color = Just Ansi.Color.Red } inner


blue : String -> Text
blue inner =
    Style { blankStyle | color = Just Ansi.Color.Blue } inner


resetColors : String
resetColors =
    ansi "[0m"


ansi : String -> String
ansi code =
    ansiPrefix ++ code


ansiPrefix : String
ansiPrefix =
    "\u{001B}"


colorToString : Ansi.Color.Color -> String
colorToString color =
    ansi <|
        case color of
            Ansi.Color.Red ->
                "[31m"

            Ansi.Color.Blue ->
                "[34m"

            Ansi.Color.Green ->
                "[32m"

            Ansi.Color.Yellow ->
                "[33m"

            Ansi.Color.Cyan ->
                "[36m"

            _ ->
                -- TODO
                ""


toString : List Text -> String
toString list =
    list
        |> List.map toString_
        |> String.concat


toString_ : Text -> String
toString_ (Style ansiStyle innerText) =
    String.concat
        [ ansiStyle.color |> Maybe.withDefault Ansi.Color.White |> colorToString
        , innerText
        , resetColors
        ]


toPlainString : List Text -> String
toPlainString list =
    list
        |> List.map (\(Style _ inner) -> inner)
        |> String.concat


fromAnsiString : String -> List Text
fromAnsiString ansiString =
    Ansi.Parser.parseInto ( blankStyle, [] ) parseInto ansiString
        |> Tuple.second
        |> List.reverse


type alias AnsiStyle =
    { bold : Bool
    , underline : Bool
    , color : Maybe Ansi.Color.Color
    }


blankStyle : AnsiStyle
blankStyle =
    { bold = False
    , underline = False
    , color = Nothing
    }


parseInto : Ansi.Parser.Command -> ( AnsiStyle, List Text ) -> ( AnsiStyle, List Text )
parseInto action ( pendingStyle, soFar ) =
    case action of
        Ansi.Parser.Text string ->
            ( blankStyle, Style pendingStyle string :: soFar )

        Ansi.Parser.Remainder _ ->
            ( pendingStyle, soFar )

        Ansi.Parser.SetForeground maybeColor ->
            case maybeColor of
                Just newColor ->
                    ( { pendingStyle
                        | color = Just newColor
                      }
                    , soFar
                    )

                Nothing ->
                    ( blankStyle, soFar )

        Ansi.Parser.SetBold bool ->
            ( { pendingStyle | bold = bool }, soFar )

        Ansi.Parser.SetFaint _ ->
            ( pendingStyle, soFar )

        Ansi.Parser.SetItalic _ ->
            ( pendingStyle, soFar )

        Ansi.Parser.SetUnderline bool ->
            ( { pendingStyle | underline = bool }, soFar )

        Ansi.Parser.SetBackground _ ->
            ( pendingStyle, soFar )

        Ansi.Parser.Linebreak ->
            case soFar of
                next :: rest ->
                    ( pendingStyle, Style blankStyle "\n" :: next :: rest )

                [] ->
                    ( pendingStyle, soFar )

        _ ->
            ( pendingStyle, soFar )


encoder : Text -> Encode.Value
encoder (Style ansiStyle string) =
    Encode.object
        [ ( "bold", Encode.bool ansiStyle.bold )
        , ( "underline", Encode.bool ansiStyle.underline )
        , ( "color"
          , Encode.string <|
                case ansiStyle.color |> Maybe.withDefault Ansi.Color.White of
                    Ansi.Color.Red ->
                        "red"

                    Ansi.Color.Blue ->
                        "blue"

                    Ansi.Color.Green ->
                        "green"

                    Ansi.Color.Yellow ->
                        "yellow"

                    Ansi.Color.Cyan ->
                        "cyan"

                    Ansi.Color.Black ->
                        "black"

                    Ansi.Color.Magenta ->
                        "magenta"

                    Ansi.Color.White ->
                        "white"

                    Ansi.Color.BrightBlack ->
                        "BLACK"

                    Ansi.Color.BrightRed ->
                        "RED"

                    Ansi.Color.BrightGreen ->
                        "GREEN"

                    Ansi.Color.BrightYellow ->
                        "YELLOW"

                    Ansi.Color.BrightBlue ->
                        "BLUE"

                    Ansi.Color.BrightMagenta ->
                        "MAGENTA"

                    Ansi.Color.BrightCyan ->
                        "CYAN"

                    Ansi.Color.BrightWhite ->
                        "WHITE"

                    Ansi.Color.Custom256 _ ->
                        ""

                    Ansi.Color.CustomTrueColor _ ->
                        ""
          )
        , ( "string", Encode.string string )
        ]
