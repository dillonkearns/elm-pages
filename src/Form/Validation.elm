module Form.Validation exposing
    ( OnlyValidation, FieldValidation, LowLevelValidation
    , andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback
    , value, fieldName
    )

{-|


## Validations

@docs OnlyValidation, FieldValidation, LowLevelValidation

@docs andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback


## Field Metadata

@docs value, fieldName

-}

import Dict exposing (Dict)
import Pages.Internal.Form exposing (Validation(..))


{-| -}
type alias OnlyValidation error parsed =
    Pages.Internal.Form.Validation error parsed Never Never


{-| -}
type alias FieldValidation error parsed kind =
    Pages.Internal.Form.Validation error parsed kind { field : kind }


{-| -}
type alias LowLevelValidation error parsed kind constraints =
    Pages.Internal.Form.Validation error parsed kind constraints


{-| -}
fieldName : FieldValidation error parsed kind -> String
fieldName (Validation viewField name ( maybeParsed, errors )) =
    name
        |> Maybe.withDefault ""


{-| -}
succeed : parsed -> OnlyValidation error parsed
succeed parsed =
    Validation Nothing Nothing ( Just parsed, Dict.empty )


{-| -}
withFallback : parsed -> LowLevelValidation error parsed named constraints -> LowLevelValidation error parsed named constraints
withFallback parsed (Validation viewField name ( maybeParsed, errors )) =
    Validation viewField
        name
        ( maybeParsed
            |> Maybe.withDefault parsed
            |> Just
        , errors
        )


{-| -}
value : LowLevelValidation error parsed named constraint -> Maybe parsed
value (Validation _ _ ( maybeParsed, _ )) =
    maybeParsed


{-| -}
parseWithError : parsed -> ( String, error ) -> OnlyValidation error parsed
parseWithError parsed ( key, error ) =
    Validation Nothing Nothing ( Just parsed, Dict.singleton key [ error ] )


{-| -}
fail : FieldValidation error parsed1 field -> error -> OnlyValidation error parsed
fail (Validation _ key _) parsed =
    -- TODO need to prevent Never fields from being used
    Validation Nothing Nothing ( Nothing, Dict.singleton (key |> Maybe.withDefault "") [ parsed ] )


{-| -}
withError : FieldValidation error parsed1 field -> error -> LowLevelValidation error parsed2 named constraints -> LowLevelValidation error parsed2 named constraints
withError (Validation _ key _) error (Validation viewField name ( maybeParsedA, errorsA )) =
    -- TODO need to prevent Never fields from being used
    Validation viewField name ( maybeParsedA, errorsA |> insertIfNonempty (key |> Maybe.withDefault "") [ error ] )


{-| -}
withErrorIf : Bool -> FieldValidation error ignored field -> error -> LowLevelValidation error parsed named constraints -> LowLevelValidation error parsed named constraints
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
map : (parsed -> mapped) -> LowLevelValidation error parsed named constraint -> OnlyValidation error mapped
map mapFn (Validation viewField name ( maybeParsedA, errorsA )) =
    Validation Nothing name ( Maybe.map mapFn maybeParsedA, errorsA )


{-| -}
fromResult : Result ( String, error ) parsed -> OnlyValidation error parsed
fromResult result =
    case result of
        Ok parsed ->
            Validation Nothing Nothing ( Just parsed, Dict.empty )

        Err ( key, error ) ->
            Validation Nothing Nothing ( Nothing, Dict.singleton key [ error ] )


{-| -}
andMap : LowLevelValidation error a named1 constraints1 -> LowLevelValidation error (a -> b) named2 constraints2 -> OnlyValidation error b
andMap =
    map2 (|>)


{-| -}
andThen : (parsed -> LowLevelValidation error mapped named1 constraints1) -> LowLevelValidation error parsed named2 constraints2 -> OnlyValidation error mapped
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
map2 : (a -> b -> c) -> LowLevelValidation error a named1 constraints1 -> LowLevelValidation error b named2 constraints2 -> OnlyValidation error c
map2 f (Validation _ name1 ( maybeParsedA, errorsA )) (Validation _ name2 ( maybeParsedB, errorsB )) =
    Validation Nothing
        Nothing
        ( Maybe.map2 f maybeParsedA maybeParsedB
        , mergeErrors errorsA errorsB
        )


{-| -}
fromMaybe : Maybe parsed -> OnlyValidation error parsed
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
