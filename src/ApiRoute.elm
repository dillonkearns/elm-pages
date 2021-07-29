module ApiRoute exposing (Done, Handler, Response, buildTimeRoutes, capture, int, literal, single, slash, succeed, getBuildTimeRoutes)

{-|

@docs Done, Handler, Response, buildTimeRoutes, capture, int, literal, single, slash, succeed, getBuildTimeRoutes

-}

import DataSource exposing (DataSource)
import Internal.ApiRoute exposing (Done(..), Handler(..))
import Regex


{-| -}
type alias Done response =
    Internal.ApiRoute.Done response


{-| -}
single : Handler (DataSource Response) (List String) -> Done Response
single handler =
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
    Done
        { regex = Regex.fromString ("^" ++ pattern ++ "$") |> Maybe.withDefault Regex.never
        , matchesToResponse =
            \path ->
                let
                    matches : List String
                    matches =
                        Internal.ApiRoute.pathToMatches path fullHandler

                    routeFound : DataSource Bool
                    routeFound =
                        preBuiltMatches
                            |> DataSource.map (List.member matches)
                in
                routeFound
                    |> DataSource.andThen
                        (\found ->
                            if found then
                                Internal.ApiRoute.tryMatch path fullHandler
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
                        Internal.ApiRoute.pathToMatches path fullHandler
                in
                preBuiltMatches
                    |> DataSource.map (List.member matches)
        }


{-| -}
type alias Handler a constructor =
    Internal.ApiRoute.Handler a constructor


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
    Handler (String -> a) constructor
    -> Handler a (String -> constructor)
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
    Handler (Int -> a) constructor
    -> Handler a (Int -> constructor)
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


{-| -}
getBuildTimeRoutes : Done response -> DataSource (List String)
getBuildTimeRoutes (Done handler) =
    handler.buildTimeRoutes



--captureRest : Handler (List String -> a) b -> Handler a b
--captureRest previousHandler =
--    Debug.todo ""
