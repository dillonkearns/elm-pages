module TerminalText exposing (..)


type Text
    = RawText String
    | Style String Text


type Color
    = Red
    | Blue


text : String -> Text
text value =
    RawText value


red : Text -> Text
red inner =
    Style (colorToString Red) inner


blue : Text -> Text
blue inner =
    Style (colorToString Blue) inner


resetColors : String
resetColors =
    ansi "[0m"


ansi code =
    ansiPrefix ++ code


ansiPrefix =
    "\u{001B}"


colorToString : Color -> String
colorToString color =
    ansi <|
        case color of
            Red ->
                "[31m"

            Blue ->
                "[34m"


toString : List Text -> String
toString list =
    list
        |> List.map toString_
        |> String.join ""


toString_ : Text -> String
toString_ textValue =
    case textValue of
        RawText content ->
            content

        Style code innerText ->
            String.concat
                [ code, toString_ innerText, resetColors ]
