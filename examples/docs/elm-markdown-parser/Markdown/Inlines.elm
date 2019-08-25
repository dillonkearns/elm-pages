module Markdown.Inlines exposing (State, Style, StyledString, isUninteresting, nextStepWhenFoundBold, nextStepWhenFoundItalic, nextStepWhenFoundNothing, parse, parseHelp)

import Browser
import Char
import Debug
import Html exposing (Html)
import Html.Attributes as Attr
import Parser
import Parser.Advanced as Advanced exposing (..)


type alias Parser a =
    Advanced.Parser String Parser.Problem a


isUninteresting : Char -> Bool
isUninteresting char =
    char /= '*'


type alias Style =
    { isBold : Bool, isItalic : Bool }


type alias StyledString =
    { style : Style, string : String }


type alias State =
    ( Style, List StyledString )


nextStepWhenFoundBold : State -> String -> Step State (List StyledString)
nextStepWhenFoundBold ( currStyle, revStyledStrings ) string =
    Loop
        ( { currStyle | isBold = not currStyle.isBold }
        , { style = currStyle, string = string } :: revStyledStrings
        )


nextStepWhenFoundItalic : State -> String -> Step State (List StyledString)
nextStepWhenFoundItalic ( currStyle, revStyledStrings ) string =
    Loop
        ( { currStyle | isItalic = not currStyle.isItalic }
        , { style = currStyle, string = string } :: revStyledStrings
        )


nextStepWhenFoundNothing : State -> String -> Step State (List StyledString)
nextStepWhenFoundNothing ( currStyle, revStyledStrings ) string =
    Done
        (List.reverse
            ({ style = currStyle, string = string } :: revStyledStrings)
        )


parse : Parser (List StyledString)
parse =
    loop ( { isBold = False, isItalic = False }, [] ) parseHelp


parseHelp : State -> Parser (Step State (List StyledString))
parseHelp state =
    andThen
        (\chompedString ->
            oneOf
                [ map
                    (\_ -> nextStepWhenFoundBold state chompedString)
                    (token (Token "**" (Parser.Expecting "**")))
                , map
                    (\_ -> nextStepWhenFoundItalic state chompedString)
                    (token (Token "*" (Parser.Expecting "*")))
                , succeed
                    (nextStepWhenFoundNothing state chompedString)
                ]
        )
        (getChompedString
            (chompWhile isUninteresting)
        )
