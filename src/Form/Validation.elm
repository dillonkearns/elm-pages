module Form.Validation exposing
    ( Validation, andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback
    , value
    , fail2, fieldName, withError2
    )

{-|

@docs Validation, andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback

@docs value

-}

import Dict exposing (Dict)
import Pages.Internal.Form exposing (Named, Validation(..))


{-| -}
type alias Validation error parsed named =
    Pages.Internal.Form.Validation error parsed named


fieldName : Validation error parsed kind -> String
fieldName (Validation viewField name ( maybeParsed, errors )) =
    name
        |> Maybe.withDefault ""


{-| -}
succeed : parsed -> Validation error parsed Never
succeed parsed =
    Validation Nothing Nothing ( Just parsed, Dict.empty )


{-| -}
withFallback : parsed -> Validation error parsed named -> Validation error parsed named
withFallback parsed (Validation viewField name ( maybeParsed, errors )) =
    Validation viewField
        name
        ( maybeParsed
            |> Maybe.withDefault parsed
            |> Just
        , errors
        )


{-| -}
value : Validation error parsed named -> Maybe parsed
value (Validation _ _ ( maybeParsed, _ )) =
    maybeParsed


{-| -}
parseWithError : parsed -> ( String, error ) -> Validation error parsed Never
parseWithError parsed ( key, error ) =
    Validation Nothing Nothing ( Just parsed, Dict.singleton key [ error ] )


{-| -}
fail : Validation error parsed1 Named -> error -> Validation error parsed Never
fail (Validation _ key _) parsed =
    Validation Nothing Nothing ( Nothing, Dict.singleton (key |> Maybe.withDefault "") [ parsed ] )


{-| -}
fail2 : Validation error parsed1 field -> error -> Validation error parsed Never
fail2 (Validation _ key _) parsed =
    -- TODO need to prevent Never fields from being used
    Validation Nothing Nothing ( Nothing, Dict.singleton (key |> Maybe.withDefault "") [ parsed ] )


{-| -}
withError : Validation error parsed1 Named -> error -> Validation error parsed2 named -> Validation error parsed2 named
withError (Validation _ key _) error (Validation viewField name ( maybeParsedA, errorsA )) =
    Validation viewField name ( maybeParsedA, errorsA |> insertIfNonempty (key |> Maybe.withDefault "") [ error ] )


{-| -}
withError2 : Validation error parsed1 field -> error -> Validation error parsed2 named -> Validation error parsed2 named
withError2 (Validation _ key _) error (Validation viewField name ( maybeParsedA, errorsA )) =
    -- TODO need to prevent Never fields from being used
    Validation viewField name ( maybeParsedA, errorsA |> insertIfNonempty (key |> Maybe.withDefault "") [ error ] )


{-| -}
withErrorIf : Bool -> Validation error ignored Named -> error -> Validation error parsed named -> Validation error parsed named
withErrorIf includeError (Validation _ key _) error (Validation viewField name ( maybeParsedA, errorsA )) =
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
map : (parsed -> mapped) -> Validation error parsed named -> Validation error mapped Never
map mapFn (Validation viewField name ( maybeParsedA, errorsA )) =
    Validation Nothing name ( Maybe.map mapFn maybeParsedA, errorsA )


{-| -}
fromResult : Result ( String, error ) parsed -> Validation error parsed Never
fromResult result =
    case result of
        Ok parsed ->
            Validation Nothing Nothing ( Just parsed, Dict.empty )

        Err ( key, error ) ->
            Validation Nothing Nothing ( Nothing, Dict.singleton key [ error ] )


{-| -}
andMap : Validation error a named1 -> Validation error (a -> b) named2 -> Validation error b Never
andMap =
    map2 (|>)


{-| -}
andThen : (parsed -> Validation error mapped named1) -> Validation error parsed named2 -> Validation error mapped Never
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
map2 : (a -> b -> c) -> Validation error a named1 -> Validation error b named2 -> Validation error c Never
map2 f (Validation _ name1 ( maybeParsedA, errorsA )) (Validation _ name2 ( maybeParsedB, errorsB )) =
    Validation Nothing
        Nothing
        ( Maybe.map2 f maybeParsedA maybeParsedB
        , mergeErrors errorsA errorsB
        )


{-| -}
fromMaybe : Maybe parsed -> Validation error parsed Never
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
