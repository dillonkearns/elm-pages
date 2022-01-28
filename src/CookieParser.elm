module CookieParser exposing (parse)

import Dict exposing (Dict)
import Parser exposing ((|.), (|=), Parser, Step(..))
import Url


parse : String -> Dict String String
parse input =
    Parser.run parser input
        |> Result.withDefault Dict.empty


parser : Parser (Dict String String)
parser =
    Parser.loop [] keyValuePair
        |> Parser.map Dict.fromList


keyValuePair : List ( String, String ) -> Parser (Step (List ( String, String )) (List ( String, String )))
keyValuePair revChunks =
    Parser.oneOf
        [ Parser.end
            |> Parser.map (\_ -> Done (List.reverse revChunks))
        , Parser.succeed (Loop revChunks)
            |. Parser.chompIf isSpace
            |. Parser.chompWhile isSpace
        , Parser.succeed Tuple.pair
            |= parseKey
            |= Parser.oneOf
                [ Parser.succeed Nothing
                    |. Parser.token ";"
                , Parser.succeed Just
                    |. Parser.token "="
                    |= valueParser
                    |. Parser.oneOf
                        [ Parser.token ";"
                        , Parser.succeed ()
                        ]
                ]
            |> Parser.andThen
                (\( key, maybeValue ) ->
                    case maybeValue of
                        Just value ->
                            Parser.succeed (Loop (( key, value ) :: revChunks))

                        Nothing ->
                            Parser.succeed (Loop revChunks)
                )
        ]


valueParser : Parser String
valueParser =
    Parser.succeed identity
        |. Parser.chompWhile isSpace
        |= Parser.oneOf
            [ Parser.succeed ""
                |. Parser.token ";"
            , Parser.succeed identity
                |. Parser.token "\""
                |= (Parser.chompUntil "\""
                        |> Parser.getChompedString
                   )
                |. Parser.token "\""
            , Parser.chompWhile (\c -> c /= ';')
                |> Parser.getChompedString
            ]
        |> Parser.map String.trim
        |> Parser.map (\value -> value |> Url.percentDecode |> Maybe.withDefault "")


parseKey : Parser String
parseKey =
    Parser.succeed identity
        |= (Parser.chompWhile (\c -> c /= '=' && c /= ';')
                |> Parser.getChompedString
                |> Parser.map String.trim
           )


isSpace : Char -> Bool
isSpace c =
    c == ' '
