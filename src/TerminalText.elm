module TerminalText exposing
    ( Color(..)
    , Text(..)
    , ansi
    , ansiPrefix
    , blue
    , colorToString
    , cyan
    , encoder
    , getString
    , green
    , red
    , resetColors
    , text
    , toString
    , toString_
    , yellow
    )

import Json.Encode as Encode


type Text
    = RawText String
    | Style Color Text


type Color
    = Red
    | Blue
    | Green
    | Yellow
    | Cyan


text : String -> Text
text value =
    RawText value


cyan : Text -> Text
cyan inner =
    Style Cyan inner


green : Text -> Text
green inner =
    Style Green inner


yellow : Text -> Text
yellow inner =
    Style Yellow inner


red : Text -> Text
red inner =
    Style Red inner


blue : Text -> Text
blue inner =
    Style Blue inner


resetColors : String
resetColors =
    ansi "[0m"


ansi : String -> String
ansi code =
    ansiPrefix ++ code


ansiPrefix : String
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

            Green ->
                "[32m"

            Yellow ->
                "[33m"

            Cyan ->
                "[36m"


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
                            Red ->
                                "red"

                            Blue ->
                                "blue"

                            Green ->
                                "green"

                            Yellow ->
                                "yellow"

                            Cyan ->
                                "cyan"
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
