module ApiRoute exposing (Done, Handler(..), Response, buildTimeRoutes, capture, firstMatch, int, literal, pathToMatches, singleRoute, slash, succeed, tryMatch, tryMatchDone, withRoutes, withRoutesNew)

{-|

@docs Done, Handler, Response, buildTimeRoutes, capture, firstMatch, int, literal, pathToMatches, singleRoute, slash, succeed, tryMatch, tryMatchDone, withRoutes, withRoutesNew

-}

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
tryMatchDone path handler =
    if Regex.contains handler.regex path then
        Just handler

    else
        Nothing


{-| -}
withRoutesNew :
    (constructor -> List (List String))
    -> Handler a constructor
    -> List String
withRoutesNew buildUrls (Handler _ _ toString constructor) =
    buildUrls (constructor [])
        |> List.map toString


{-| -}
type alias Done response =
    { regex : Regex
    , matchesToResponse : String -> DataSource (Maybe response)
    , buildTimeRoutes : DataSource (List String)
    , handleRoute : String -> DataSource Bool
    }


{-| -}
singleRoute : Handler (DataSource Response) (List String) -> Done Response
singleRoute handler =
    handler
        |> buildTimeRoutes (\constructor -> DataSource.succeed [ constructor ])


{-| -}
buildTimeRoutes : (constructor -> DataSource (List (List String))) -> Handler (DataSource Response) constructor -> Done Response
buildTimeRoutes buildUrls ((Handler pattern _ toString constructor) as fullHandler) =
    let
        buildTimeRoutes__ : DataSource (List String)
        buildTimeRoutes__ =
            buildUrls (constructor [])
                |> DataSource.map (List.map toString)

        preBuiltMatches : DataSource (List (List String))
        preBuiltMatches =
            buildUrls (constructor [])
    in
    { regex = Regex.fromString ("^" ++ pattern ++ "$") |> Maybe.withDefault Regex.never
    , matchesToResponse =
        \path ->
            let
                matches : List String
                matches =
                    pathToMatches path fullHandler

                routeFound : DataSource Bool
                routeFound =
                    preBuiltMatches
                        |> DataSource.map (List.member matches)
            in
            routeFound
                |> DataSource.andThen
                    (\found ->
                        if found then
                            tryMatch path fullHandler
                                |> Maybe.map (DataSource.map Just)
                                |> Maybe.withDefault (DataSource.succeed Nothing)

                        else
                            DataSource.succeed Nothing
                    )
    , buildTimeRoutes = buildTimeRoutes__
    , handleRoute =
        \path ->
            let
                matches : List String
                matches =
                    pathToMatches path fullHandler
            in
            preBuiltMatches
                |> DataSource.map (List.member matches)
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


{-| -}
type alias Response =
    { body : String }


{-| -}
succeed : a -> Handler a (List String)
succeed a =
    Handler "" (\_ -> a) (\_ -> "") (\list -> list)


{-| -}
literal : String -> Handler a constructor -> Handler a constructor
literal segment (Handler pattern handler toString constructor) =
    Handler (pattern ++ segment) handler (\values -> toString values ++ segment) constructor


{-| -}
slash : Handler a constructor -> Handler a constructor
slash (Handler pattern handler toString constructor) =
    Handler (pattern ++ "/") handler (\arg -> toString arg ++ "/") constructor


{-| -}
capture :
    Handler
        (String -> a)
        constructor
    ->
        Handler
            a
            (String -> constructor)
capture (Handler pattern previousHandler toString constructor) =
    Handler
        (pattern ++ "(.*)")
        (\matches ->
            case matches of
                first :: rest ->
                    previousHandler rest first

                _ ->
                    previousHandler [] "Error"
        )
        (\s ->
            case s of
                first :: rest ->
                    toString rest ++ first

                _ ->
                    ""
        )
        (\matches ->
            \string ->
                constructor (string :: matches)
        )


{-| -}
int :
    Handler
        (Int -> a)
        constructor
    ->
        Handler
            a
            (Int -> constructor)
int (Handler pattern previousHandler toString constructor) =
    Handler
        (pattern ++ "(\\d+)")
        (\matches ->
            case matches of
                first :: rest ->
                    previousHandler rest (String.toInt first |> Maybe.withDefault -1)

                _ ->
                    previousHandler [] -1
        )
        (\s ->
            case s of
                first :: rest ->
                    toString rest ++ first

                _ ->
                    ""
        )
        (\matches ->
            \string ->
                constructor (String.fromInt string :: matches)
        )



--captureRest : Handler (List String -> a) b -> Handler a b
--captureRest previousHandler =
--    Debug.todo ""
