module Validation exposing (Validation, andMap, andThen, fail, fromMaybe, fromResult, map, map2, succeed, withField)

import Dict exposing (Dict)


type alias Validation error parsed =
    ( Maybe parsed, Dict String (List error) )


succeed : parsed -> Validation error parsed
succeed parsed =
    ( Just parsed, Dict.empty )


fail : String -> error -> Validation error parsed
fail key parsed =
    ( Nothing, Dict.singleton key [ parsed ] )


map : (parsed -> mapped) -> Validation error parsed -> Validation error mapped
map mapFn ( maybeParsedA, errorsA ) =
    ( Maybe.map mapFn maybeParsedA, errorsA )


fromResult : Result ( String, error ) parsed -> Validation error parsed
fromResult result =
    case result of
        Ok parsed ->
            ( Just parsed, Dict.empty )

        Err ( key, error ) ->
            ( Nothing, Dict.singleton key [ error ] )


andMap : Validation error a -> Validation error (a -> b) -> Validation error b
andMap =
    map2 (|>)


withField : { field | value : Validation error parsed } -> Validation error (parsed -> combined) -> Validation error combined
withField field =
    andMap field.value


andThen : (parsed -> Validation error mapped) -> Validation error parsed -> Validation error mapped
andThen andThenFn ( maybeParsed, errors ) =
    case maybeParsed of
        Just parsed ->
            andThenFn parsed
                |> Tuple.mapSecond (mergeErrors errors)

        Nothing ->
            ( Nothing, errors )


map2 : (a -> b -> c) -> Validation error a -> Validation error b -> Validation error c
map2 f ( maybeParsedA, errorsA ) ( maybeParsedB, errorsB ) =
    ( Maybe.map2 f maybeParsedA maybeParsedB
    , mergeErrors errorsA errorsB
    )


fromMaybe : Maybe parsed -> Validation error parsed
fromMaybe maybe =
    ( maybe, Dict.empty )


mergeErrors : Dict comparable (List value) -> Dict comparable (List value) -> Dict comparable (List value)
mergeErrors errors1 errors2 =
    Dict.merge
        (\key entries soFar ->
            soFar |> insertIfNonempty key entries
        )
        (\key entries1 entries2 soFar ->
            soFar |> insertIfNonempty key (entries1 ++ entries2)
        )
        (\key entries soFar ->
            soFar |> insertIfNonempty key entries
        )
        errors1
        errors2
        Dict.empty


insertIfNonempty : comparable -> List value -> Dict comparable (List value) -> Dict comparable (List value)
insertIfNonempty key values dict =
    if values |> List.isEmpty then
        dict

    else
        dict
            |> Dict.insert key values
