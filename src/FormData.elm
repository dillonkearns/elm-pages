module FormData exposing (parse)

import Dict exposing (Dict)
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


decode : String -> String
decode string =
    string
        |> String.replace "+" " "
        |> Url.percentDecode
        |> Maybe.withDefault ""
