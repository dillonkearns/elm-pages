module Pages.Internal.Router exposing (Matcher, firstMatch, fromOptionalSplat, maybeToList, nonEmptyToList, toNonEmpty)

{-| Exposed for internal use only (used in generated code).

@docs Matcher, firstMatch, fromOptionalSplat, maybeToList, nonEmptyToList, toNonEmpty

-}

import List.Extra
import Regex


{-| -}
firstMatch : List (Matcher route) -> String -> Maybe route
firstMatch matchers path =
    List.Extra.findMap
        (\matcher ->
            if Regex.contains (matcher.pattern |> toRegex) (normalizePath path) then
                tryMatch matcher path

            else
                Nothing
        )
        matchers


toRegex : String -> Regex.Regex
toRegex pattern =
    Regex.fromString pattern
        |> Maybe.withDefault Regex.never


{-| -}
nonEmptyToList : ( String, List String ) -> List String
nonEmptyToList ( string, strings ) =
    string :: strings


{-| -}
fromOptionalSplat : Maybe String -> List String
fromOptionalSplat maybeMatch =
    maybeMatch
        |> Maybe.map (\match -> match |> String.split "/")
        |> Maybe.map (List.filter (\item -> item /= ""))
        |> Maybe.withDefault []


{-| -}
maybeToList : Maybe String -> List String
maybeToList maybeString =
    case maybeString of
        Just string ->
            [ string ]

        Nothing ->
            []


{-| -}
toNonEmpty : String -> ( String, List String )
toNonEmpty string =
    case string |> String.split "/" of
        [] ->
            ( "ERROR", [] )

        first :: rest ->
            ( first, rest )


{-| -}
type alias Matcher route =
    { pattern : String, toRoute : List (Maybe String) -> Maybe route }


{-| -}
tryMatch : { pattern : String, toRoute : List (Maybe String) -> Maybe route } -> String -> Maybe route
tryMatch { pattern, toRoute } path =
    path
        |> normalizePath
        |> submatches pattern
        |> toRoute


submatches : String -> String -> List (Maybe String)
submatches pattern path =
    Regex.find
        (Regex.fromString pattern
            |> Maybe.withDefault Regex.never
        )
        path
        |> List.concatMap .submatches


normalizePath : String -> String
normalizePath path =
    path
        |> ensureLeadingSlash
        |> stripTrailingSlash


ensureLeadingSlash : String -> String
ensureLeadingSlash path =
    if path |> String.startsWith "/" then
        path

    else
        "/" ++ path


stripTrailingSlash : String -> String
stripTrailingSlash path =
    if (path |> String.endsWith "/") && (String.length path > 1) then
        String.dropRight 1 path

    else
        path
