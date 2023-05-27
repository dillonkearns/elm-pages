module FormData exposing (encode, parse, parseToList)

import Dict exposing (Dict)
import List.NonEmpty exposing (NonEmpty)
import Url


parse : String -> Dict String ( String, List String )
parse rawString =
    rawString
        |> String.split "&"
        |> List.foldl
            (\entry soFar ->
                case entry |> String.split "=" of
                    [ key, value ] ->
                        let
                            newValue : String
                            newValue =
                                value |> decode
                        in
                        Dict.update (decode key)
                            (\maybeExistingList ->
                                maybeExistingList
                                    |> Maybe.map (\( first, rest ) -> ( first, rest ++ [ newValue ] ))
                                    |> Maybe.withDefault ( newValue, [] )
                                    |> Just
                            )
                            soFar

                    _ ->
                        --( entry |> Url.percentDecode |> Maybe.withDefault entry, ( "", [] ) )
                        soFar
            )
            Dict.empty


parseToList : String -> List ( String, String )
parseToList rawString =
    rawString
        |> String.split "&"
        |> List.concatMap
            (\entry ->
                case entry |> String.split "=" of
                    [ key, value ] ->
                        let
                            newValue : String
                            newValue =
                                value |> decode
                        in
                        [ ( key, newValue ) ]

                    _ ->
                        []
            )


decode : String -> String
decode string =
    string
        |> String.replace "+" " "
        |> Url.percentDecode
        |> Maybe.withDefault ""


encode : Dict String (NonEmpty String) -> String
encode dict =
    dict
        |> Dict.toList
        |> List.concatMap
            (\( key, values ) ->
                values
                    |> List.NonEmpty.toList
                    |> List.map
                        (\value ->
                            Url.percentEncode key ++ "=" ++ Url.percentEncode value
                        )
            )
        |> String.join "&"
