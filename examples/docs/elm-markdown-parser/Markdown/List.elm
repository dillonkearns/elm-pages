module Markdown.List exposing (..)

import Browser
import Char
import Html exposing (Html)
import Html.Attributes as Attr
import Markdown.Inlines
import Parser
import Parser.Advanced as Advanced exposing (..)


type alias Parser a =
    Advanced.Parser String Parser.Problem a


type alias ListItem =
    List Markdown.Inlines.StyledString


parser : Parser (List ListItem)
parser =
    singleItemParser
        |> andThen
            (\firstItem ->
                loop [] (statementsHelp firstItem)
            )


singleItemParser : Parser ListItem
singleItemParser =
    succeed
        identity
        |. Advanced.symbol (Advanced.Token "-" (Parser.ExpectingSymbol "-"))
        |. chompWhile (\c -> c == ' ')
        |= (Advanced.getChompedString (Advanced.chompUntilEndOr "\n")
                |> andThen
                    (\listItemContent ->
                        case listItemContent |> Advanced.run Markdown.Inlines.parse of
                            Ok content ->
                                succeed content

                            Err errors ->
                                problem (Parser.Expecting "Error parsing inlines TODO")
                    )
           )
        |. Advanced.symbol (Advanced.Token "\n" (Parser.ExpectingSymbol "\n"))


statementsHelp : ListItem -> List ListItem -> Parser (Step (List ListItem) (List ListItem))
statementsHelp firstItem revStmts =
    oneOf
        [ succeed
            (\offsetBefore stmt offsetAfter ->
                -- let
                --     madeProgress =
                --         offsetAfter
                --             > offsetBefore
                --             |> Debug.log "progress"
                -- in
                -- if madeProgress then
                Loop (stmt :: revStmts)
             --
             -- else
             --     Done (List.reverse (stmt :: revStmts))
            )
            |= Advanced.getOffset
            |= singleItemParser
            |= Advanced.getOffset

        -- TODO this is causing files to require newlines
        -- at the end... how do I avoid this?
        -- |. symbol (Advanced.Token "\n" (Parser.Expecting "newline"))
        , succeed ()
            |> map (\_ -> Done (firstItem :: List.reverse revStmts))
        ]



-- |= getChompedString
--     (chompUntilEndOr
--         (Advanced.Token "\n" (Parser.ExpectingSymbol "\n"))
--     )
-- |. Advanced.symbol (Advanced.Token "]" (Parser.ExpectingSymbol "]"))
-- |. Advanced.symbol (Advanced.Token "(" (Parser.ExpectingSymbol "("))
-- |= getChompedString
--     (chompUntil (Advanced.Token ")" (Parser.ExpectingSymbol ")")))
-- |. Advanced.symbol (Advanced.Token ")" (Parser.ExpectingSymbol ")"))
-- isUninteresting : Char -> Bool
-- isUninteresting char =
--     char /= '*' && char /= '`'
