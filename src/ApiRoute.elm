module ApiRoute exposing
    ( ApiRoute, ApiRouteBuilder, Response, buildTimeRoutes, capture, int, literal, single, slash, succeed, getBuildTimeRoutes
    , singleServerless, toPattern
    )

{-| ApiRoute's are defined in `src/Api.elm` and are a way to generate files, like RSS feeds, sitemaps, or any text-based file that you output with an Elm function! You get access
to a DataSource so you can pull in HTTP data, etc. Because ApiRoutes don't hydrate into Elm apps (like pages in elm-pages do), you can pull in as much data as you want in
the DataSource for your ApiRoutes, and it won't effect the payload size. Instead, the size of an ApiRoute is just the content you output for that route.

In a future release, ApiRoutes may be able to run at request-time in a serverless function, allowing you to use pure Elm code to create dynamic APIs, and even pulling in data from
DataSources dynamically.

@docs ApiRoute, ApiRouteBuilder, Response, buildTimeRoutes, capture, int, literal, single, slash, succeed, getBuildTimeRoutes

-}

import DataSource exposing (DataSource)
import Internal.ApiRoute exposing (ApiRoute(..), ApiRouteBuilder(..))
import Pattern exposing (Pattern)
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
singleServerless : ApiRouteBuilder (DataSource Response) (List String) -> ApiRoute Response
singleServerless handler =
    handler
        |> buildTimeRoutes (\constructor -> DataSource.succeed [ constructor ])


{-| -}
buildTimeRoutes : (constructor -> DataSource (List (List String))) -> ApiRouteBuilder (DataSource Response) constructor -> ApiRoute Response
buildTimeRoutes buildUrls ((ApiRouteBuilder patterns pattern _ toString constructor) as fullHandler) =
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
        , pattern = patterns
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
    ApiRouteBuilder Pattern.empty "" (\_ -> a) (\_ -> "") (\list -> list)



--toPattern : ApiRouteBuilder a b -> Pattern


toPattern : ApiRoute response -> Pattern
toPattern =
    Internal.ApiRoute.toPattern


{-| -}
literal : String -> ApiRouteBuilder a constructor -> ApiRouteBuilder a constructor
literal segment (ApiRouteBuilder patterns pattern handler toString constructor) =
    ApiRouteBuilder
        (Pattern.addLiteral segment patterns)
        (pattern ++ segment)
        handler
        (\values -> toString values ++ segment)
        constructor


{-| -}
slash : ApiRouteBuilder a constructor -> ApiRouteBuilder a constructor
slash (ApiRouteBuilder patterns pattern handler toString constructor) =
    ApiRouteBuilder (patterns |> Pattern.addSlash) (pattern ++ "/") handler (\arg -> toString arg ++ "/") constructor


{-| -}
capture :
    ApiRouteBuilder (String -> a) constructor
    -> ApiRouteBuilder a (String -> constructor)
capture (ApiRouteBuilder patterns pattern previousHandler toString constructor) =
    ApiRouteBuilder
        (patterns |> Pattern.addCapture)
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
int (ApiRouteBuilder patterns pattern previousHandler toString constructor) =
    ApiRouteBuilder
        patterns
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


{-| For internal use by generated code. Not so useful in user-land.
-}
getBuildTimeRoutes : ApiRoute response -> DataSource (List String)
getBuildTimeRoutes (ApiRoute handler) =
    handler.buildTimeRoutes



--captureRest : ApiRouteBuilder (List String -> a) b -> ApiRouteBuilder a b
--captureRest previousHandler =
--    Debug.todo ""
