module ApiRoute exposing (ApiRoute, ApiRouteBuilder, Response, buildTimeRoutes, capture, int, literal, single, slash, succeed, getBuildTimeRoutes)

{-|

@docs ApiRoute, ApiRouteBuilder, Response, buildTimeRoutes, capture, int, literal, single, slash, succeed, getBuildTimeRoutes

-}

import DataSource exposing (DataSource)
import Internal.ApiRoute exposing (ApiRoute(..), ApiRouteBuilder(..))
import Regex


{-| -}
type alias ApiRoute response =
    Internal.ApiRoute.ApiRoute response


{-| -}
single : ApiRouteBuilder (DataSource Response) (List String) -> ApiRoute Response
single handler =
    handler
        |> buildTimeRoutes (\constructor -> DataSource.succeed [ constructor ])


{-| -}
buildTimeRoutes : (constructor -> DataSource (List (List String))) -> ApiRouteBuilder (DataSource Response) constructor -> ApiRoute Response
buildTimeRoutes buildUrls ((ApiRouteBuilder pattern _ toString constructor) as fullHandler) =
    let
        buildTimeRoutes__ : DataSource (List String)
        buildTimeRoutes__ =
            buildUrls (constructor [])
                |> DataSource.map (List.map toString)

        preBuiltMatches : DataSource (List (List String))
        preBuiltMatches =
            buildUrls (constructor [])
    in
    ApiRoute
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
type alias ApiRouteBuilder a constructor =
    Internal.ApiRoute.ApiRouteBuilder a constructor


{-| -}
type alias Response =
    { body : String }


{-| -}
succeed : a -> ApiRouteBuilder a (List String)
succeed a =
    ApiRouteBuilder "" (\_ -> a) (\_ -> "") (\list -> list)


{-| -}
literal : String -> ApiRouteBuilder a constructor -> ApiRouteBuilder a constructor
literal segment (ApiRouteBuilder pattern handler toString constructor) =
    ApiRouteBuilder (pattern ++ segment) handler (\values -> toString values ++ segment) constructor


{-| -}
slash : ApiRouteBuilder a constructor -> ApiRouteBuilder a constructor
slash (ApiRouteBuilder pattern handler toString constructor) =
    ApiRouteBuilder (pattern ++ "/") handler (\arg -> toString arg ++ "/") constructor


{-| -}
capture :
    ApiRouteBuilder (String -> a) constructor
    -> ApiRouteBuilder a (String -> constructor)
capture (ApiRouteBuilder pattern previousHandler toString constructor) =
    ApiRouteBuilder
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
    ApiRouteBuilder (Int -> a) constructor
    -> ApiRouteBuilder a (Int -> constructor)
int (ApiRouteBuilder pattern previousHandler toString constructor) =
    ApiRouteBuilder
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
getBuildTimeRoutes : ApiRoute response -> DataSource (List String)
getBuildTimeRoutes (ApiRoute handler) =
    handler.buildTimeRoutes



--captureRest : ApiRouteBuilder (List String -> a) b -> ApiRouteBuilder a b
--captureRest previousHandler =
--    Debug.todo ""
