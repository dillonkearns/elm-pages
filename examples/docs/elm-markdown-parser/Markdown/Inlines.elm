module Markdown.Inlines exposing (LinkUrl(..), State, Style, StyledString, isUninteresting, nextStepWhenFoundBold, nextStepWhenFoundItalic, nextStepWhenFoundNothing, parse, parseHelp, toString)

import Browser
import Char
import Debug
import Html exposing (Html)
import Html.Attributes as Attr
import Markdown.Link as Link exposing (Link)
import Parser
import Parser.Advanced as Advanced exposing (..)


toString : List StyledString -> String
toString list =
    List.map .string list
        |> String.join "-"


type alias Parser a =
    Advanced.Parser String Parser.Problem a


isUninteresting : Char -> Bool
isUninteresting char =
    char
        /= '*'
        && char
        /= '`'
        && char
        /= '['
        && char
        /= '!'


type alias Style =
    { isCode : Bool
    , isBold : Bool
    , isItalic : Bool
    , link : Maybe { title : Maybe String, destination : LinkUrl }
    }


type LinkUrl
    = Image String
    | Link String


type alias StyledString =
    { style : Style, string : String }


type alias State =
    ( Style, List StyledString, Maybe String )


nextStepWhenFoundBold : State -> String -> Step State (List StyledString)
nextStepWhenFoundBold ( currStyle, revStyledStrings, _ ) string =
    Loop
        ( { currStyle | isBold = not currStyle.isBold }
        , { style = currStyle, string = string } :: revStyledStrings
        , Nothing
        )


nextStepWhenFoundLink : Link -> State -> String -> Step State (List StyledString)
nextStepWhenFoundLink link ( currStyle, revStyledStrings, _ ) string =
    case link of
        Link.Link record ->
            Loop
                ( currStyle
                , { style = { currStyle | link = Just { title = record.title, destination = Link record.destination } }, string = record.description }
                    :: { style = currStyle, string = string }
                    :: revStyledStrings
                , Nothing
                )

        Link.Image record ->
            Loop
                ( currStyle
                , { style = { currStyle | link = Just { title = Nothing, destination = Image record.src } }, string = record.alt }
                    :: { style = currStyle, string = string }
                    :: revStyledStrings
                , Nothing
                )


nextStepWhenFoundCode : State -> String -> Step State (List StyledString)
nextStepWhenFoundCode ( currStyle, revStyledStrings, _ ) string =
    Loop
        ( { currStyle | isCode = not currStyle.isCode }
        , { style = currStyle, string = string } :: revStyledStrings
        , Nothing
        )


nextStepWhenFoundItalic : State -> String -> Step State (List StyledString)
nextStepWhenFoundItalic ( currStyle, revStyledStrings, _ ) string =
    Loop
        ( { currStyle | isItalic = not currStyle.isItalic }
        , { style = currStyle, string = string } :: revStyledStrings
        , Nothing
        )


nextStepWhenFoundNothing : State -> String -> Step State (List StyledString)
nextStepWhenFoundNothing ( currStyle, revStyledStrings, _ ) string =
    Done
        (List.reverse
            ({ style = currStyle, string = string } :: revStyledStrings)
            |> List.filter (\thing -> thing.string /= "")
        )


nextStepWhenAllFailed : State -> String -> Step State (List StyledString)
nextStepWhenAllFailed ( currStyle, revStyledStrings, _ ) string =
    Loop
        ( currStyle, revStyledStrings, Just string )


parse : Parser (List StyledString)
parse =
    loop
        ( { isCode = False
          , isBold = False
          , isItalic = False
          , link = Nothing
          }
        , []
        , Nothing
        )
        parseHelp


parseHelp : State -> Parser (Step State (List StyledString))
parseHelp (( _, _, allFailed ) as state) =
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
                , succeed identity
                    |= succeed (nextStepWhenFoundNothing state chompedString)
                    |. end (Parser.Expecting "End of inlines")
                , succeed (nextStepWhenAllFailed state chompedString)
                ]
        )
        (case allFailed of
            Nothing ->
                getChompedString (chompWhile isUninteresting)

            Just unhanldedString ->
                succeed (\chomped -> unhanldedString ++ chomped)
                    |= getChompedString (chompIf (\_ -> True) (Parser.Expecting "*"))
        )
