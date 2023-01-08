module Internal.ApiRoute exposing
    ( ApiRoute(..)
    , ApiRouteBuilder(..)
    , firstMatch
    , pathToMatches
    , toPattern
    , tryMatch
    , withRoutes
    )

import BackendTask exposing (BackendTask)
import Exception exposing (Throwable)
import Head
import Json.Decode
import Pattern exposing (Pattern)
import Regex exposing (Regex)


{-| -}
firstMatch : String -> List (ApiRoute response) -> Maybe (ApiRoute response)
firstMatch path handlers =
    case handlers of
        [] ->
            Nothing

        first :: rest ->
            case tryMatchDone path first of
                Just response ->
                    Just response

                Nothing ->
                    firstMatch path rest


{-| -}
tryMatchDone : String -> ApiRoute response -> Maybe (ApiRoute response)
tryMatchDone path (ApiRoute handler) =
    if Regex.contains handler.regex path then
        Just (ApiRoute handler)

    else
        Nothing


{-| -}
type ApiRoute response
    = ApiRoute
        { regex : Regex
        , matchesToResponse : Json.Decode.Value -> String -> BackendTask Throwable (Maybe response)
        , buildTimeRoutes : BackendTask Throwable (List String)
        , handleRoute : String -> BackendTask Throwable Bool
        , pattern : Pattern
        , kind : String
        , globalHeadTags : Maybe (BackendTask Throwable (List Head.Tag))
        }


toPattern : ApiRoute response -> Pattern
toPattern (ApiRoute { pattern }) =
    pattern


{-| -}
pathToMatches : String -> ApiRouteBuilder a constructor -> List String
pathToMatches path (ApiRouteBuilder _ pattern _ _ _) =
    Regex.find
        (Regex.fromString pattern
            |> Maybe.withDefault Regex.never
        )
        path
        |> List.concatMap .submatches
        |> List.filterMap identity
        |> List.reverse


{-| -}
withRoutes : (constructor -> List (List String)) -> ApiRouteBuilder a constructor -> List String
withRoutes buildUrls (ApiRouteBuilder _ _ _ toString constructor) =
    buildUrls (constructor [])
        |> List.map toString


{-| -}
tryMatch : String -> ApiRouteBuilder response constructor -> Maybe response
tryMatch path (ApiRouteBuilder _ pattern handler _ _) =
    let
        matches : List String
        matches =
            Regex.find
                (Regex.fromString pattern
                    |> Maybe.withDefault Regex.never
                )
                path
                |> List.concatMap .submatches
                |> List.filterMap identity
                |> List.reverse
    in
    handler matches
        |> Just


{-| -}
type ApiRouteBuilder a constructor
    = ApiRouteBuilder Pattern String (List String -> a) (List String -> String) (List String -> constructor)
