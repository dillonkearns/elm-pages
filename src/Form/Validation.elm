module Form.Validation exposing
    ( Combined, Field, Validation
    , andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback
    , value, fieldName
    )

{-|


## Validations

@docs Combined, Field, Validation

@docs andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback


## Field Metadata

@docs value, fieldName

-}

import Dict exposing (Dict)
import Pages.Internal.Form exposing (Validation(..))


{-| -}
type alias Combined error parsed =
    Pages.Internal.Form.Validation error parsed Never Never


{-| -}
type alias Field error parsed kind =
    Pages.Internal.Form.Validation error parsed kind { field : kind }


{-| -}
type alias Validation error parsed kind constraints =
    Pages.Internal.Form.Validation error parsed kind constraints


{-| -}
fieldName : Field error parsed kind -> String
fieldName (Validation viewField name ( maybeParsed, errors )) =
    name
        |> Maybe.withDefault ""


{-| -}
succeed : parsed -> Combined error parsed
succeed parsed =
    Validation Nothing Nothing ( Just parsed, Dict.empty )


{-| -}
withFallback : parsed -> Validation error parsed named constraints -> Validation error parsed named constraints
withFallback parsed (Validation viewField name ( maybeParsed, errors )) =
    Validation viewField
        name
        ( maybeParsed
            |> Maybe.withDefault parsed
            |> Just
        , errors
        )


{-| -}
value : Validation error parsed named constraint -> Maybe parsed
value (Validation _ _ ( maybeParsed, _ )) =
    maybeParsed


{-| -}
parseWithError : parsed -> ( String, error ) -> Combined error parsed
parseWithError parsed ( key, error ) =
    Validation Nothing Nothing ( Just parsed, Dict.singleton key [ error ] )


{-| -}
fail : Field error parsed1 field -> error -> Combined error parsed
fail (Validation _ key _) parsed =
    -- TODO need to prevent Never fields from being used
    Validation Nothing Nothing ( Nothing, Dict.singleton (key |> Maybe.withDefault "") [ parsed ] )


{-| -}
withError : Field error parsed1 field -> error -> Validation error parsed2 named constraints -> Validation error parsed2 named constraints
withError (Validation _ key _) error (Validation viewField name ( maybeParsedA, errorsA )) =
    -- TODO need to prevent Never fields from being used
    Validation viewField name ( maybeParsedA, errorsA |> insertIfNonempty (key |> Maybe.withDefault "") [ error ] )


{-| -}
withErrorIf : Bool -> Field error ignored field -> error -> Validation error parsed named constraints -> Validation error parsed named constraints
withErrorIf includeError (Validation _ key _) error (Validation viewField name ( maybeParsedA, errorsA )) =
    -- TODO use something like { field : kind } for type variable to check that it represents a field
    Validation viewField
        name
        ( maybeParsedA
        , if includeError then
            errorsA |> insertIfNonempty (key |> Maybe.withDefault "") [ error ]

          else
            errorsA
        )



--map : (parsed -> mapped) -> Validation error parsed named -> Validation error mapped named


{-| -}
map : (parsed -> mapped) -> Validation error parsed named constraint -> Combined error mapped
map mapFn (Validation viewField name ( maybeParsedA, errorsA )) =
    Validation Nothing name ( Maybe.map mapFn maybeParsedA, errorsA )


{-| -}
fromResult : Result ( String, error ) parsed -> Combined error parsed
fromResult result =
    case result of
        Ok parsed ->
            Validation Nothing Nothing ( Just parsed, Dict.empty )

        Err ( key, error ) ->
            Validation Nothing Nothing ( Nothing, Dict.singleton key [ error ] )


{-| -}
andMap : Validation error a named1 constraints1 -> Validation error (a -> b) named2 constraints2 -> Combined error b
andMap =
    map2 (|>)


{-| -}
andThen : (parsed -> Validation error mapped named1 constraints1) -> Validation error parsed named2 constraints2 -> Combined error mapped
andThen andThenFn (Validation _ name ( maybeParsed, errors )) =
    case maybeParsed of
        Just parsed ->
            andThenFn parsed
                |> (\(Validation _ _ ( andThenParsed, andThenErrors )) ->
                        Validation Nothing Nothing ( andThenParsed, mergeErrors errors andThenErrors )
                   )

        Nothing ->
            Validation Nothing Nothing ( Nothing, errors )


{-| -}
map2 : (a -> b -> c) -> Validation error a named1 constraints1 -> Validation error b named2 constraints2 -> Combined error c
map2 f (Validation _ name1 ( maybeParsedA, errorsA )) (Validation _ name2 ( maybeParsedB, errorsB )) =
    Validation Nothing
        Nothing
        ( Maybe.map2 f maybeParsedA maybeParsedB
        , mergeErrors errorsA errorsB
        )


{-| -}
fromMaybe : Maybe parsed -> Combined error parsed
fromMaybe maybe =
    Validation Nothing Nothing ( maybe, Dict.empty )


{-| -}
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


{-| -}
insertIfNonempty : comparable -> List value -> Dict comparable (List value) -> Dict comparable (List value)
insertIfNonempty key values dict =
    if values |> List.isEmpty then
        dict

    else
        dict
            |> Dict.insert key values
