module Internal.ApiRoute exposing
    ( Done(..)
    , Handler(..)
    , firstMatch
    , pathToMatches
    , tryMatch
    , withRoutes
    )

import DataSource exposing (DataSource)
import Regex exposing (Regex)


{-| -}
firstMatch : String -> List (Done response) -> Maybe (Done response)
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
tryMatchDone : String -> Done response -> Maybe (Done response)
tryMatchDone path (Done handler) =
    if Regex.contains handler.regex path then
        Just (Done handler)

    else
        Nothing


{-| -}
type Done response
    = Done
        { regex : Regex
        , matchesToResponse : String -> DataSource (Maybe response)
        , buildTimeRoutes : DataSource (List String)
        , handleRoute : String -> DataSource Bool
        }


{-| -}
pathToMatches : String -> Handler a constructor -> List String
pathToMatches path (Handler pattern _ _ _) =
    Regex.find
        (Regex.fromString pattern
            |> Maybe.withDefault Regex.never
        )
        path
        |> List.concatMap .submatches
        |> List.filterMap identity


{-| -}
withRoutes : (constructor -> List (List String)) -> Handler a constructor -> List String
withRoutes buildUrls (Handler _ _ toString constructor) =
    buildUrls (constructor [])
        |> List.map toString


{-| -}
tryMatch : String -> Handler response constructor -> Maybe response
tryMatch path (Handler pattern handler _ _) =
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
type Handler a constructor
    = Handler String (List String -> a) (List String -> String) (List String -> constructor)
