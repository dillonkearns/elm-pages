module QueryParams exposing
    ( QueryParams
    , fromString
    , toString
    )

{-| Represents the query portion of a URL. You can use `toDict` or `toString` to turn it into basic types, or you can
parse it into a custom type using the other functions in this module.

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
type alias QueryParams =
    Dict String (List String)


{-| -}
toString : QueryParams -> String
toString queryParams =
    queryParams
        |> Dict.toList
        |> List.concatMap
            (\( key, values ) ->
                values
                    |> List.map
                        (\value ->
                            key ++ "=" ++ value
                        )
            )
        |> String.join "&"


{-| -}
fromString : String -> Dict String (List String)
fromString queryParams =
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
