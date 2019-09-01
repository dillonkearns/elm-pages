module Markdown.CodeBlock exposing (..)

import Parser
import Parser.Advanced as Advanced exposing (..)


type alias Parser a =
    Advanced.Parser String Parser.Problem a


parser : Parser CodeBlock
parser =
    oneOf
        [ parserHelp "```"
        , parserHelp "~~~"
        , indentedBlock
        ]


indentedBlock : Parser CodeBlock
indentedBlock =
    succeed
        (\body ->
            { body = body
            , language = Nothing
            }
        )
        |. oneOf
            [ Advanced.symbol (Advanced.Token "    " (Parser.ExpectingSymbol "Indentation"))
            , Advanced.symbol (Advanced.Token "\t" (Parser.ExpectingSymbol "Indentation"))
            ]
        |= getChompedString (Advanced.chompUntilEndOr "\n")


parserHelp : String -> Parser CodeBlock
parserHelp delimeter =
    succeed
        (\language body ->
            { body = body
            , language =
                if language == "" then
                    Nothing

                else
                    Just language
            }
        )
        |. Advanced.symbol (Advanced.Token delimeter (Parser.ExpectingSymbol delimeter))
        |= getChompedString (chompUntil (Advanced.Token "\n" (Parser.Problem "Expecting newline")))
        |. Advanced.symbol (Advanced.Token "\n" (Parser.ExpectingSymbol "\n"))
        |= getChompedString (Advanced.chompUntilEndOr ("\n" ++ delimeter))
        |. Advanced.symbol (Advanced.Token ("\n" ++ delimeter) (Parser.ExpectingSymbol delimeter))



-- |. Advanced.symbol (Advanced.Token "\n" (Parser.ExpectingSymbol "\n"))
-- |. Advanced.symbol (Advanced.Token delimeter (Parser.ExpectingSymbol delimeter))


type alias CodeBlock =
    { body : String
    , language : Maybe String
    }
