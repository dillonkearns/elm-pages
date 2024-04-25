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

import Ansi
import Json.Encode as Encode


type Text
    = Style AnsiStyle String


text : String -> Text
text value =
    Style blankStyle value


cyan : String -> Text
cyan inner =
    Style { blankStyle | color = Just Ansi.Cyan } inner


green : String -> Text
green inner =
    Style { blankStyle | color = Just Ansi.Green } inner


yellow : String -> Text
yellow inner =
    Style { blankStyle | color = Just Ansi.Yellow } inner


red : String -> Text
red inner =
    Style { blankStyle | color = Just Ansi.Red } inner


blue : String -> Text
blue inner =
    Style { blankStyle | color = Just Ansi.Blue } inner


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
        |> String.concat


toString_ : Text -> String
toString_ (Style ansiStyle innerText) =
    String.concat
        [ ansiStyle.color |> Maybe.withDefault Ansi.White |> colorToString
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
    Ansi.parseInto ( blankStyle, [] ) parseInto ansiString
        |> Tuple.second
        |> List.reverse


type alias AnsiStyle =
    { bold : Bool
    , underline : Bool
    , color : Maybe Ansi.Color
    }


blankStyle : AnsiStyle
blankStyle =
    { bold = False
    , underline = False
    , color = Nothing
    }


parseInto : Ansi.Action -> ( AnsiStyle, List Text ) -> ( AnsiStyle, List Text )
parseInto action ( pendingStyle, soFar ) =
    case action of
        Ansi.Print string ->
            ( blankStyle, Style pendingStyle string :: soFar )

        Ansi.Remainder _ ->
            ( pendingStyle, soFar )

        Ansi.SetForeground maybeColor ->
            case maybeColor of
                Just newColor ->
                    ( { pendingStyle
                        | color = Just newColor
                      }
                    , soFar
                    )

                Nothing ->
                    ( blankStyle, soFar )

        Ansi.SetBold bool ->
            ( { pendingStyle | bold = bool }, soFar )

        Ansi.SetFaint _ ->
            ( pendingStyle, soFar )

        Ansi.SetItalic _ ->
            ( pendingStyle, soFar )

        Ansi.SetUnderline bool ->
            ( { pendingStyle | underline = bool }, soFar )

        Ansi.SetBackground _ ->
            ( pendingStyle, soFar )

        Ansi.Linebreak ->
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
                case ansiStyle.color |> Maybe.withDefault Ansi.White of
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
                        ""
          )
        , ( "string", Encode.string string )
        ]
