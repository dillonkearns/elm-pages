module QueryParams exposing (Parser, QueryParams, fromString, optionalString, parse, string, strings, toDict)

import Dict exposing (Dict)
import Url


type QueryParams
    = QueryParams String


type Parser a
    = Parser (Dict String (List String) -> Result String a)


optionalString : String -> Parser (Maybe String)
optionalString key =
    custom key
        (\stringList ->
            case stringList of
                str :: rest ->
                    Ok (Just str)

                _ ->
                    Ok Nothing
        )


string : String -> Parser String
string key =
    custom key
        (\stringList ->
            case stringList of
                [ str ] ->
                    Ok str

                _ ->
                    Err ("Missing key " ++ key)
        )


custom : String -> (List String -> Result String a) -> Parser a
custom key customFn =
    Parser <|
        \dict ->
            customFn (Maybe.withDefault [] (Dict.get key dict))


strings : String -> Parser (List String)
strings key =
    custom key
        (\stringList -> Ok stringList)


fromString : String -> QueryParams
fromString =
    QueryParams


parse : Parser a -> QueryParams -> Result String a
parse (Parser queryParser) queryParams =
    queryParams
        |> toDict
        |> queryParser


toDict : QueryParams -> Dict String (List String)
toDict (QueryParams queryParams) =
    prepareQuery (Just queryParams)


prepareQuery : Maybe String -> Dict String (List String)
prepareQuery maybeQuery =
    case maybeQuery of
        Nothing ->
            Dict.empty

        Just qry ->
            List.foldr addParam Dict.empty (String.split "&" qry)


addParam : String -> Dict String (List String) -> Dict String (List String)
addParam segment dict =
    case String.split "=" segment of
        [ rawKey, rawValue ] ->
            case Url.percentDecode rawKey of
                Nothing ->
                    dict

                Just key ->
                    case Url.percentDecode rawValue of
                        Nothing ->
                            dict

                        Just value ->
                            Dict.update key (addToParametersHelp value) dict

        _ ->
            dict


addToParametersHelp : a -> Maybe (List a) -> Maybe (List a)
addToParametersHelp value maybeList =
    case maybeList of
        Nothing ->
            Just [ value ]

        Just list ->
            Just (value :: list)
