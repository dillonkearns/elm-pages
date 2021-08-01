module Internal.ApiRoute exposing
    ( ApiRoute(..)
    , ApiRouteBuilder(..)
    , firstMatch
    , pathToMatches
    , tryMatch
    , withRoutes
    )

import DataSource exposing (DataSource)
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
        , matchesToResponse : String -> DataSource (Maybe response)
        , buildTimeRoutes : DataSource (List String)
        , handleRoute : String -> DataSource Bool
        }


{-| -}
pathToMatches : String -> ApiRouteBuilder a constructor -> List String
pathToMatches path (ApiRouteBuilder pattern _ _ _) =
    Regex.find
        (Regex.fromString pattern
            |> Maybe.withDefault Regex.never
        )
        path
        |> List.concatMap .submatches
        |> List.filterMap identity


{-| -}
withRoutes : (constructor -> List (List String)) -> ApiRouteBuilder a constructor -> List String
withRoutes buildUrls (ApiRouteBuilder _ _ toString constructor) =
    buildUrls (constructor [])
        |> List.map toString


{-| -}
tryMatch : String -> ApiRouteBuilder response constructor -> Maybe response
tryMatch path (ApiRouteBuilder pattern handler _ _) =
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
    in
    handler matches
        |> Just


{-| -}
type ApiRouteBuilder a constructor
    = ApiRouteBuilder String (List String -> a) (List String -> String) (List String -> constructor)
