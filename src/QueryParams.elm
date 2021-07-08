module QueryParams exposing
    ( QueryParams
    , Parser
    , andThen, fail, fromResult, fromString, optionalString, parse, string, strings, succeed
    , map2, oneOf
    , toDict, toString
    )

{-|

@docs QueryParams


## Parsing

@docs Parser

@docs andThen, fail, fromResult, fromString, optionalString, parse, string, strings, succeed


## Combining

@docs map2, oneOf


## Accessing as Built-In Types

@docs toDict, toString

-}

import Dict exposing (Dict)
import Url


{-| -}
type QueryParams
    = QueryParams String


{-| -}
type Parser a
    = Parser (Dict String (List String) -> Result String a)


{-| -}
succeed : a -> Parser a
succeed value =
    Parser (\_ -> Ok value)


{-| -}
fail : String -> Parser a
fail errorMessage =
    Parser (\_ -> Err errorMessage)


{-| -}
fromResult : Result String a -> Parser a
fromResult result =
    Parser (\_ -> result)


{-| -}
andThen : (a -> Parser b) -> Parser a -> Parser b
andThen andThenFn (Parser parser) =
    Parser
        (\dict ->
            case Result.map andThenFn (parser dict) of
                Ok (Parser result) ->
                    result dict

                Err error ->
                    Err error
        )


{-| -}
oneOf : List (Parser a) -> Parser a
oneOf parsers =
    Parser
        (tryParser parsers)


{-| -}
tryParser : List (Parser a) -> Dict String (List String) -> Result String a
tryParser parsers dict =
    case parsers of
        [] ->
            Err ""

        (Parser nextParser) :: otherParsers ->
            case nextParser dict of
                Ok okValue ->
                    Ok okValue

                Err _ ->
                    tryParser otherParsers dict


{-| -}
map2 : (a -> b -> combined) -> Parser a -> Parser b -> Parser combined
map2 func (Parser a) (Parser b) =
    Parser <|
        \dict ->
            Result.map2 func (a dict) (b dict)


{-| -}
optionalString : String -> Parser (Maybe String)
optionalString key =
    custom key
        (\stringList ->
            case stringList of
                str :: _ ->
                    Ok (Just str)

                _ ->
                    Ok Nothing
        )


{-| -}
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


{-| -}
custom : String -> (List String -> Result String a) -> Parser a
custom key customFn =
    Parser <|
        \dict ->
            customFn (Maybe.withDefault [] (Dict.get key dict))


{-| -}
strings : String -> Parser (List String)
strings key =
    custom key
        (\stringList -> Ok stringList)


{-| -}
fromString : String -> QueryParams
fromString =
    QueryParams


{-| -}
toString : QueryParams -> String
toString (QueryParams queryParams) =
    queryParams


{-| -}
parse : Parser a -> QueryParams -> Result String a
parse (Parser queryParser) queryParams =
    queryParams
        |> toDict
        |> queryParser


{-| -}
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
