module Form.Validation exposing
    ( Combined, Field, Validation
    , andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback
    , value, fieldName
    , FieldStatus(..), fieldStatus, fieldStatusToString
    , statusAtLeast
    , map3, map4, map5, map6, map7, map8, map9
    , mapToCombined
    , global
    )

{-|


## Validations

@docs Combined, Field, Validation

@docs andMap, andThen, fail, fromMaybe, fromResult, map, map2, parseWithError, succeed, withError, withErrorIf, withFallback


## Field Metadata

@docs value, fieldName

@docs FieldStatus, fieldStatus, fieldStatusToString

@docs statusAtLeast


## Mapping

@docs map3, map4, map5, map6, map7, map8, map9

@docs mapToCombined


## Global Validation

@docs global

-}

import Dict exposing (Dict)
import Form.FieldStatus exposing (FieldStatus)
import Pages.Internal.Form exposing (ViewField)


{-| -}
type alias Combined error parsed =
    Validation error parsed Never Never


{-| -}
type alias Field error parsed kind =
    Validation error parsed kind { field : kind }


{-| -}
type alias Validation error parsed kind constraints =
    Pages.Internal.Form.Validation error parsed kind constraints


{-| -}
fieldName : Field error parsed kind -> String
fieldName (Pages.Internal.Form.Validation _ name _) =
    name
        |> Maybe.withDefault ""


{-| -}
fieldStatus : Field error parsed kind -> FieldStatus
fieldStatus (Pages.Internal.Form.Validation viewField _ _) =
    viewField
        |> expectViewField
        |> .status
        |> statusFromRank


{-| -}
fieldStatusToString : FieldStatus -> String
fieldStatusToString status =
    case status of
        NotVisited ->
            "NotVisited"

        Focused ->
            "Focused"

        Changed ->
            "Changed"

        Blurred ->
            "Blurred"


{-| -}
statusAtLeast : FieldStatus -> Field error parsed kind -> Bool
statusAtLeast status field =
    (field |> fieldStatus |> statusRank) >= statusRank status


{-| -}
type FieldStatus
    = NotVisited
    | Focused
    | Changed
    | Blurred


statusFromRank : Int -> FieldStatus
statusFromRank int =
    case int of
        0 ->
            NotVisited

        1 ->
            Focused

        2 ->
            Changed

        3 ->
            Blurred

        _ ->
            Blurred


{-| -}
statusRank : FieldStatus -> Int
statusRank status =
    case status of
        NotVisited ->
            0

        Focused ->
            1

        Changed ->
            2

        Blurred ->
            3


expectViewField : Maybe (ViewField kind) -> ViewField kind
expectViewField viewField =
    case viewField of
        Just justViewField ->
            justViewField

        Nothing ->
            expectViewField viewField


{-| -}
succeed : parsed -> Combined error parsed
succeed parsed =
    Pages.Internal.Form.Validation Nothing Nothing ( Just parsed, Dict.empty )


{-| -}
global : Field error () Never
global =
    Pages.Internal.Form.Validation Nothing
        (Just "$$global$$")
        ( Just ()
        , Dict.empty
        )


{-| -}
withFallback : parsed -> Validation error parsed named constraints -> Validation error parsed named constraints
withFallback parsed (Pages.Internal.Form.Validation viewField name ( maybeParsed, errors )) =
    Pages.Internal.Form.Validation viewField
        name
        ( maybeParsed
            |> Maybe.withDefault parsed
            |> Just
        , errors
        )


{-| -}
value : Validation error parsed named constraint -> Maybe parsed
value (Pages.Internal.Form.Validation _ _ ( maybeParsed, _ )) =
    maybeParsed


{-| -}
parseWithError : parsed -> ( String, error ) -> Combined error parsed
parseWithError parsed ( key, error ) =
    Pages.Internal.Form.Validation Nothing Nothing ( Just parsed, Dict.singleton key [ error ] )


{-| -}
fail : error -> Field error parsed1 field -> Combined error parsed
fail parsed (Pages.Internal.Form.Validation _ key _) =
    Pages.Internal.Form.Validation Nothing Nothing ( Nothing, Dict.singleton (key |> Maybe.withDefault "") [ parsed ] )


{-| -}
withError : Field error parsed1 field -> error -> Validation error parsed2 named constraints -> Validation error parsed2 named constraints
withError (Pages.Internal.Form.Validation _ key _) error (Pages.Internal.Form.Validation viewField name ( maybeParsedA, errorsA )) =
    Pages.Internal.Form.Validation viewField name ( maybeParsedA, errorsA |> insertIfNonempty (key |> Maybe.withDefault "") [ error ] )


{-| -}
withErrorIf : Bool -> Field error ignored field -> error -> Validation error parsed named constraints -> Validation error parsed named constraints
withErrorIf includeError (Pages.Internal.Form.Validation _ key _) error (Pages.Internal.Form.Validation viewField name ( maybeParsedA, errorsA )) =
    Pages.Internal.Form.Validation viewField
        name
        ( maybeParsedA
        , if includeError then
            errorsA |> insertIfNonempty (key |> Maybe.withDefault "") [ error ]

          else
            errorsA
        )



--map : (parsed -> mapped) -> Validation error parsed named -> Validation error mapped named


{-| -}
map : (parsed -> mapped) -> Validation error parsed named constraint -> Validation error mapped named constraint
map mapFn (Pages.Internal.Form.Validation _ name ( maybeParsedA, errorsA )) =
    Pages.Internal.Form.Validation Nothing name ( Maybe.map mapFn maybeParsedA, errorsA )


{-| -}
mapToCombined : (parsed -> mapped) -> Validation error parsed named constraint -> Combined error mapped
mapToCombined mapFn (Pages.Internal.Form.Validation _ name ( maybeParsedA, errorsA )) =
    Pages.Internal.Form.Validation Nothing name ( Maybe.map mapFn maybeParsedA, errorsA )


{-| -}
fromResult : Field error (Result error parsed) kind -> Combined error parsed
fromResult fieldResult =
    fieldResult
        |> andThen
            (\parsedValue ->
                case parsedValue of
                    Ok okValue ->
                        succeed okValue

                    Err error ->
                        fail error fieldResult
            )


{-| -}
andMap : Validation error a named1 constraints1 -> Validation error (a -> b) named2 constraints2 -> Combined error b
andMap =
    map2 (|>)


{-| -}
andThen : (parsed -> Validation error mapped named1 constraints1) -> Validation error parsed named2 constraints2 -> Combined error mapped
andThen andThenFn (Pages.Internal.Form.Validation _ _ ( maybeParsed, errors )) =
    case maybeParsed of
        Just parsed ->
            andThenFn parsed
                |> (\(Pages.Internal.Form.Validation _ _ ( andThenParsed, andThenErrors )) ->
                        Pages.Internal.Form.Validation Nothing Nothing ( andThenParsed, mergeErrors errors andThenErrors )
                   )

        Nothing ->
            Pages.Internal.Form.Validation Nothing Nothing ( Nothing, errors )


{-| -}
map2 : (a -> b -> c) -> Validation error a named1 constraints1 -> Validation error b named2 constraints2 -> Combined error c
map2 f (Pages.Internal.Form.Validation _ _ ( maybeParsedA, errorsA )) (Pages.Internal.Form.Validation _ _ ( maybeParsedB, errorsB )) =
    Pages.Internal.Form.Validation Nothing
        Nothing
        ( Maybe.map2 f maybeParsedA maybeParsedB
        , mergeErrors errorsA errorsB
        )


{-| -}
map3 :
    (a1 -> a2 -> a3 -> a4)
    -> Validation error a1 named1 constraints1
    -> Validation error a2 named2 constraints2
    -> Validation error a3 named3 constraints3
    -> Combined error a4
map3 f validation1 validation2 validation3 =
    succeed f
        |> andMap validation1
        |> andMap validation2
        |> andMap validation3


{-| -}
map4 :
    (a1 -> a2 -> a3 -> a4 -> a5)
    -> Validation error a1 named1 constraints1
    -> Validation error a2 named2 constraints2
    -> Validation error a3 named3 constraints3
    -> Validation error a4 named4 constraints4
    -> Combined error a5
map4 f validation1 validation2 validation3 validation4 =
    succeed f
        |> andMap validation1
        |> andMap validation2
        |> andMap validation3
        |> andMap validation4


{-| -}
map5 :
    (a1 -> a2 -> a3 -> a4 -> a5 -> a6)
    -> Validation error a1 named1 constraints1
    -> Validation error a2 named2 constraints2
    -> Validation error a3 named3 constraints3
    -> Validation error a4 named4 constraints4
    -> Validation error a5 named5 constraints5
    -> Combined error a6
map5 f validation1 validation2 validation3 validation4 validation5 =
    succeed f
        |> andMap validation1
        |> andMap validation2
        |> andMap validation3
        |> andMap validation4
        |> andMap validation5


{-| -}
map6 :
    (a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7)
    -> Validation error a1 named1 constraints1
    -> Validation error a2 named2 constraints2
    -> Validation error a3 named3 constraints3
    -> Validation error a4 named4 constraints4
    -> Validation error a5 named5 constraints5
    -> Validation error a6 named6 constraints6
    -> Combined error a7
map6 f validation1 validation2 validation3 validation4 validation5 validation6 =
    succeed f
        |> andMap validation1
        |> andMap validation2
        |> andMap validation3
        |> andMap validation4
        |> andMap validation5
        |> andMap validation6


{-| -}
map7 :
    (a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8)
    -> Validation error a1 named1 constraints1
    -> Validation error a2 named2 constraints2
    -> Validation error a3 named3 constraints3
    -> Validation error a4 named4 constraints4
    -> Validation error a5 named5 constraints5
    -> Validation error a6 named6 constraints6
    -> Validation error a7 named7 constraints7
    -> Combined error a8
map7 f validation1 validation2 validation3 validation4 validation5 validation6 validation7 =
    succeed f
        |> andMap validation1
        |> andMap validation2
        |> andMap validation3
        |> andMap validation4
        |> andMap validation5
        |> andMap validation6
        |> andMap validation7


{-| -}
map8 :
    (a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> a9)
    -> Validation error a1 named1 constraints1
    -> Validation error a2 named2 constraints2
    -> Validation error a3 named3 constraints3
    -> Validation error a4 named4 constraints4
    -> Validation error a5 named5 constraints5
    -> Validation error a6 named6 constraints6
    -> Validation error a7 named7 constraints7
    -> Validation error a8 named8 constraints8
    -> Combined error a9
map8 f validation1 validation2 validation3 validation4 validation5 validation6 validation7 validation8 =
    succeed f
        |> andMap validation1
        |> andMap validation2
        |> andMap validation3
        |> andMap validation4
        |> andMap validation5
        |> andMap validation6
        |> andMap validation7
        |> andMap validation8


{-| -}
map9 :
    (a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> a9 -> a10)
    -> Validation error a1 named1 constraints1
    -> Validation error a2 named2 constraints2
    -> Validation error a3 named3 constraints3
    -> Validation error a4 named4 constraints4
    -> Validation error a5 named5 constraints5
    -> Validation error a6 named6 constraints6
    -> Validation error a7 named7 constraints7
    -> Validation error a8 named8 constraints8
    -> Validation error a9 named9 constraints9
    -> Combined error a10
map9 f validation1 validation2 validation3 validation4 validation5 validation6 validation7 validation8 validation9 =
    succeed f
        |> andMap validation1
        |> andMap validation2
        |> andMap validation3
        |> andMap validation4
        |> andMap validation5
        |> andMap validation6
        |> andMap validation7
        |> andMap validation8
        |> andMap validation9


{-| -}
fromMaybe : Maybe parsed -> Combined error parsed
fromMaybe maybe =
    Pages.Internal.Form.Validation Nothing Nothing ( maybe, Dict.empty )


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
