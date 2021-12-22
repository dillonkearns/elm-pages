module CookieParser exposing (parse)

import Dict exposing (Dict)
import Parser exposing (..)
import Url


parse : String -> Dict String String
parse input =
    Parser.run parser input
        |> Result.withDefault Dict.empty


parser : Parser (Dict String String)
parser =
    loop [] keyValuePair
        |> Parser.map Dict.fromList


keyValuePair : List ( String, String ) -> Parser (Step (List ( String, String )) (List ( String, String )))
keyValuePair revChunks =
    oneOf
        [ end
            |> map (\_ -> Done (List.reverse revChunks))
        , succeed (Loop revChunks)
            |. chompIf isSpace
            |. chompWhile isSpace
        , succeed Tuple.pair
            |= parseKey
            |= oneOf
                [ succeed Nothing
                    |. token ";"
                , succeed Just
                    |. token "="
                    |= valueParser
                    |. oneOf
                        [ token ";"
                        , succeed ()
                        ]
                ]
            |> andThen
                (\( key, maybeValue ) ->
                    case maybeValue of
                        Just value ->
                            succeed (Loop (( key, value ) :: revChunks))

                        Nothing ->
                            succeed (Loop revChunks)
                )
        ]


valueParser : Parser String
valueParser =
    succeed identity
        |. chompWhile isSpace
        |= oneOf
            [ succeed ""
                |. token ";"
            , succeed identity
                |. token "\""
                |= (chompUntil "\""
                        |> getChompedString
                   )
                |. token "\""
            , chompWhile (\c -> c /= ';')
                |> getChompedString
            ]
        |> map String.trim
        |> map (\value -> value |> Url.percentDecode |> Maybe.withDefault "")


parseKey : Parser String
parseKey =
    succeed identity
        |= (chompWhile (\c -> c /= '=' && c /= ';')
                |> getChompedString
                |> map String.trim
           )


isSpace : Char -> Bool
isSpace c =
    c == ' '
