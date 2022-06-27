module Validation exposing (Validation(..), andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withField)

import Dict exposing (Dict)


type Validation error parsed
    = Validation ( Maybe parsed, Dict String (List error) )


succeed : parsed -> Validation error parsed
succeed parsed =
    Validation ( Just parsed, Dict.empty )


parseWithError : parsed -> ( String, error ) -> Validation error parsed
parseWithError parsed ( key, error ) =
    Validation ( Just parsed, Dict.singleton key [ error ] )


fail : String -> error -> Validation error parsed
fail key parsed =
    Validation ( Nothing, Dict.singleton key [ parsed ] )


withError : String -> error -> Validation error parsed -> Validation error parsed
withError key error (Validation ( maybeParsedA, errorsA )) =
    Validation ( maybeParsedA, errorsA |> insertIfNonempty key [ error ] )


withErrorIf : Bool -> String -> error -> Validation error parsed -> Validation error parsed
withErrorIf includeError key error (Validation ( maybeParsedA, errorsA )) =
    Validation
        ( maybeParsedA
        , if includeError then
            errorsA |> insertIfNonempty key [ error ]

          else
            errorsA
        )


map : (parsed -> mapped) -> Validation error parsed -> Validation error mapped
map mapFn (Validation ( maybeParsedA, errorsA )) =
    Validation ( Maybe.map mapFn maybeParsedA, errorsA )


fromResult : Result ( String, error ) parsed -> Validation error parsed
fromResult result =
    case result of
        Ok parsed ->
            Validation ( Just parsed, Dict.empty )

        Err ( key, error ) ->
            Validation ( Nothing, Dict.singleton key [ error ] )


andMap : Validation error a -> Validation error (a -> b) -> Validation error b
andMap =
    map2 (|>)


withField : { field | value : Validation error parsed } -> Validation error (parsed -> combined) -> Validation error combined
withField field =
    andMap field.value


andThen : (parsed -> Validation error mapped) -> Validation error parsed -> Validation error mapped
andThen andThenFn (Validation ( maybeParsed, errors )) =
    case maybeParsed of
        Just parsed ->
            andThenFn parsed
                |> (\(Validation ( andThenParsed, andThenErrors )) ->
                        Validation ( andThenParsed, mergeErrors errors andThenErrors )
                   )

        Nothing ->
            Validation ( Nothing, errors )


map2 : (a -> b -> c) -> Validation error a -> Validation error b -> Validation error c
map2 f (Validation ( maybeParsedA, errorsA )) (Validation ( maybeParsedB, errorsB )) =
    Validation
        ( Maybe.map2 f maybeParsedA maybeParsedB
        , mergeErrors errorsA errorsB
        )


fromMaybe : Maybe parsed -> Validation error parsed
fromMaybe maybe =
    Validation ( maybe, Dict.empty )


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
