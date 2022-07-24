module Form.Validation exposing
    ( Validation, FieldValidation, AnyValidation
    , andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback
    , value, fieldName
    )

{-|


## Validations

@docs Validation, FieldValidation, AnyValidation

@docs andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback


## Field Metadata

@docs value, fieldName

-}

import Dict exposing (Dict)
import Pages.Internal.Form exposing (AnyValidation(..))


{-| -}
type alias Validation error parsed =
    Pages.Internal.Form.AnyValidation error parsed Never Never


{-| -}
type alias FieldValidation error parsed kind =
    Pages.Internal.Form.AnyValidation error parsed kind { field : kind }


{-| -}
type alias AnyValidation error parsed kind constraints =
    Pages.Internal.Form.AnyValidation error parsed kind constraints


{-| -}
fieldName : FieldValidation error parsed kind -> String
fieldName (Validation viewField name ( maybeParsed, errors )) =
    name
        |> Maybe.withDefault ""


{-| -}
succeed : parsed -> Validation error parsed
succeed parsed =
    Validation Nothing Nothing ( Just parsed, Dict.empty )


{-| -}
withFallback : parsed -> AnyValidation error parsed named constraints -> AnyValidation error parsed named constraints
withFallback parsed (Validation viewField name ( maybeParsed, errors )) =
    Validation viewField
        name
        ( maybeParsed
            |> Maybe.withDefault parsed
            |> Just
        , errors
        )


{-| -}
value : AnyValidation error parsed named constraint -> Maybe parsed
value (Validation _ _ ( maybeParsed, _ )) =
    maybeParsed


{-| -}
parseWithError : parsed -> ( String, error ) -> Validation error parsed
parseWithError parsed ( key, error ) =
    Validation Nothing Nothing ( Just parsed, Dict.singleton key [ error ] )


{-| -}
fail : FieldValidation error parsed1 field -> error -> Validation error parsed
fail (Validation _ key _) parsed =
    -- TODO need to prevent Never fields from being used
    Validation Nothing Nothing ( Nothing, Dict.singleton (key |> Maybe.withDefault "") [ parsed ] )


{-| -}
withError : FieldValidation error parsed1 field -> error -> AnyValidation error parsed2 named constraints -> AnyValidation error parsed2 named constraints
withError (Validation _ key _) error (Validation viewField name ( maybeParsedA, errorsA )) =
    -- TODO need to prevent Never fields from being used
    Validation viewField name ( maybeParsedA, errorsA |> insertIfNonempty (key |> Maybe.withDefault "") [ error ] )


{-| -}
withErrorIf : Bool -> FieldValidation error ignored field -> error -> AnyValidation error parsed named constraints -> AnyValidation error parsed named constraints
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
map : (parsed -> mapped) -> AnyValidation error parsed named constraint -> Validation error mapped
map mapFn (Validation viewField name ( maybeParsedA, errorsA )) =
    Validation Nothing name ( Maybe.map mapFn maybeParsedA, errorsA )


{-| -}
fromResult : Result ( String, error ) parsed -> Validation error parsed
fromResult result =
    case result of
        Ok parsed ->
            Validation Nothing Nothing ( Just parsed, Dict.empty )

        Err ( key, error ) ->
            Validation Nothing Nothing ( Nothing, Dict.singleton key [ error ] )


{-| -}
andMap : AnyValidation error a named1 constraints1 -> AnyValidation error (a -> b) named2 constraints2 -> Validation error b
andMap =
    map2 (|>)


{-| -}
andThen : (parsed -> AnyValidation error mapped named1 constraints1) -> AnyValidation error parsed named2 constraints2 -> Validation error mapped
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
map2 : (a -> b -> c) -> AnyValidation error a named1 constraints1 -> AnyValidation error b named2 constraints2 -> Validation error c
map2 f (Validation _ name1 ( maybeParsedA, errorsA )) (Validation _ name2 ( maybeParsedB, errorsB )) =
    Validation Nothing
        Nothing
        ( Maybe.map2 f maybeParsedA maybeParsedB
        , mergeErrors errorsA errorsB
        )


{-| -}
fromMaybe : Maybe parsed -> Validation error parsed
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
