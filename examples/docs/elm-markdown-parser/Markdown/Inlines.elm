module Markdown.Inlines exposing (State, Style, StyledString, isUninteresting, nextStepWhenFoundBold, nextStepWhenFoundItalic, nextStepWhenFoundNothing, parse, parseHelp)

import Browser
import Char
import Html exposing (Html)
import Html.Attributes as Attr
import Markdown.Link as Link exposing (Link)
import Parser
import Parser.Advanced as Advanced exposing (..)


type alias Parser a =
    Advanced.Parser String Parser.Problem a


isUninteresting : Char -> Bool
isUninteresting char =
    char /= '*' && char /= '`' && char /= '['


type alias Style =
    { isCode : Bool
    , isBold : Bool
    , isItalic : Bool
    , link : Maybe { title : Maybe String, destination : String }
    }


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


nextStepWhenFoundLink : Link -> State -> String -> Step State (List StyledString)
nextStepWhenFoundLink link ( currStyle, revStyledStrings ) string =
    Loop
        -- TODO
        {-
           | link =
               { title = Nothing
               , description = currStyle.link.description |> Maybe.withDefault ""
               , destination = currStyle.link.destination |> Maybe.withDefault ""
               }
        -}
        ( currStyle
        , { style = { currStyle | link = Just { title = link.title, destination = link.destination } }, string = link.description } :: revStyledStrings
        )


nextStepWhenFoundCode : State -> String -> Step State (List StyledString)
nextStepWhenFoundCode ( currStyle, revStyledStrings ) string =
    Loop
        ( { currStyle | isCode = not currStyle.isCode }
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
            |> List.filter (\thing -> thing.string /= "")
        )


parse : Parser (List StyledString)
parse =
    loop
        ( { isCode = False
          , isBold = False
          , isItalic = False
          , link = Nothing
          }
        , []
        )
        parseHelp


parseHelp : State -> Parser (Step State (List StyledString))
parseHelp state =
    andThen
        (\chompedString ->
            oneOf
                [ Link.parser
                    |> map (\link -> nextStepWhenFoundLink link state chompedString)
                , map
                    (\_ -> nextStepWhenFoundCode state chompedString)
                    (token (Token "`" (Parser.Expecting "`")))
                , map
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
