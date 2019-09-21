module Markdown.Link exposing (..)

import Browser
import Char
import Html exposing (Html)
import Html.Attributes as Attr
import Parser
import Parser.Advanced as Advanced exposing (..)


type alias Parser a =
    Advanced.Parser String Parser.Problem a


type Link
    = Link { description : String, title : Maybe String, destination : String }
    | Image { alt : String, src : String }


parser : Parser Link
parser =
    oneOf
        [ succeed
            (\alt src ->
                Image
                    { alt = alt
                    , src = src
                    }
            )
            |. Advanced.symbol (Advanced.Token "![" (Parser.ExpectingSymbol "["))
            |= getChompedString
                (chompUntil (Advanced.Token "]" (Parser.ExpectingSymbol "]")))
            |. Advanced.symbol (Advanced.Token "]" (Parser.ExpectingSymbol "]"))
            |. Advanced.symbol (Advanced.Token "(" (Parser.ExpectingSymbol "("))
            |= getChompedString
                (chompUntil (Advanced.Token ")" (Parser.ExpectingSymbol ")")))
            |. Advanced.symbol (Advanced.Token ")" (Parser.ExpectingSymbol ")"))
        , succeed
            (\description destination ->
                Link
                    { description = description
                    , title = Nothing
                    , destination = destination
                    }
            )
            |. Advanced.symbol (Advanced.Token "[" (Parser.ExpectingSymbol "["))
            |= getChompedString
                (chompUntil (Advanced.Token "]" (Parser.ExpectingSymbol "]")))
            |. Advanced.symbol (Advanced.Token "]" (Parser.ExpectingSymbol "]"))
            |. Advanced.symbol (Advanced.Token "(" (Parser.ExpectingSymbol "("))
            |= getChompedString
                (chompUntil (Advanced.Token ")" (Parser.ExpectingSymbol ")")))
            |. Advanced.symbol (Advanced.Token ")" (Parser.ExpectingSymbol ")"))
        ]
