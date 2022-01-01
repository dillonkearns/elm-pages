module ApiRoute exposing
    ( ApiRoute, ApiRouteBuilder, Response
    , capture, literal, slash, succeed
    , single, preRender
    , preRenderWithFallback, serverRender
    , toJson, getBuildTimeRoutes
    )

{-| ApiRoute's are defined in `src/Api.elm` and are a way to generate files, like RSS feeds, sitemaps, or any text-based file that you output with an Elm function! You get access
to a DataSource so you can pull in HTTP data, etc. Because ApiRoutes don't hydrate into Elm apps (like pages in elm-pages do), you can pull in as much data as you want in
the DataSource for your ApiRoutes, and it won't effect the payload size. Instead, the size of an ApiRoute is just the content you output for that route.

In a future release, ApiRoutes may be able to run at request-time in a serverless function, allowing you to use pure Elm code to create dynamic APIs, and even pulling in data from
DataSources dynamically.

@docs ApiRoute, ApiRouteBuilder, Response

@docs capture, literal, slash, succeed


## Pre-Rendering

@docs single, preRender


## Server Rendering

@docs preRenderWithFallback, serverRender


## Internals

@docs toJson, getBuildTimeRoutes

-}

import DataSource exposing (DataSource)
import DataSource.Http
import Internal.ApiRoute exposing (ApiRoute(..), ApiRouteBuilder(..))
import Json.Encode
import OptimizedDecoder
import Pattern exposing (Pattern)
import Regex
import Secrets
import Server.Request
import Server.Response


{-| -}
type alias ApiRoute response =
    Internal.ApiRoute.ApiRoute response


{-| -}
single : ApiRouteBuilder (DataSource String) (List String) -> ApiRoute Response
single handler =
    handler
        |> preRender (\constructor -> DataSource.succeed [ constructor ])


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


{-| -}
serverRender : ApiRouteBuilder (Server.Request.Request (DataSource Server.Response.Response)) constructor -> ApiRoute Response
serverRender ((ApiRouteBuilder patterns pattern _ toString constructor) as fullHandler) =
    ApiRoute
        { regex = Regex.fromString ("^" ++ pattern ++ "$") |> Maybe.withDefault Regex.never
        , matchesToResponse =
            \path ->
                Internal.ApiRoute.tryMatch path fullHandler
                    |> Maybe.map
                        (\toDataSource ->
                            DataSource.Http.get
                                (Secrets.succeed "$$elm-pages$$headers")
                                (OptimizedDecoder.oneOf
                                    [ toDataSource |> Server.Request.getDecoder |> OptimizedDecoder.map Just
                                    ]
                                )
                                |> DataSource.andThen
                                    (\rendered ->
                                        case rendered of
                                            Just (Ok okRendered) ->
                                                okRendered

                                            Just (Err errors) ->
                                                errors
                                                    |> Server.Request.errorsToString
                                                    |> Server.Response.stringBody
                                                    |> Server.Response.withStatusCode 400
                                                    |> DataSource.succeed

                                            Nothing ->
                                                Server.Response.stringBody "No matching request handler"
                                                    |> Server.Response.withStatusCode 400
                                                    |> DataSource.succeed
                                    )
                        )
                    |> Maybe.map (DataSource.map (Server.Response.toJson >> Just))
                    |> Maybe.withDefault
                        (DataSource.succeed Nothing)
        , buildTimeRoutes = DataSource.succeed []
        , handleRoute =
            \path ->
                DataSource.succeed
                    (case Internal.ApiRoute.tryMatch path fullHandler of
                        Just _ ->
                            True

                        Nothing ->
                            False
                    )
        , pattern = patterns
        , kind = "serverless"
        }


{-| -}
preRenderWithFallback : (constructor -> DataSource (List (List String))) -> ApiRouteBuilder (DataSource Server.Response.Response) constructor -> ApiRoute Response
preRenderWithFallback buildUrls ((ApiRouteBuilder patterns pattern _ toString constructor) as fullHandler) =
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
                Internal.ApiRoute.tryMatch path fullHandler
                    |> Maybe.map (DataSource.map (Server.Response.toJson >> Just))
                    |> Maybe.withDefault
                        (DataSource.succeed Nothing)
        , buildTimeRoutes = buildTimeRoutes__
        , handleRoute =
            \path ->
                DataSource.succeed
                    (case Internal.ApiRoute.tryMatch path fullHandler of
                        Just _ ->
                            True

                        Nothing ->
                            False
                    )
        , pattern = patterns
        , kind = "prerender-with-fallback"
        }


encodeStaticFileBody : String -> Response
encodeStaticFileBody fileBody =
    Json.Encode.object
        [ ( "body", fileBody |> Json.Encode.string )
        , ( "kind", Json.Encode.string "static-file" )
        ]


{-| -}
preRender : (constructor -> DataSource (List (List String))) -> ApiRouteBuilder (DataSource String) constructor -> ApiRoute Response
preRender buildUrls ((ApiRouteBuilder patterns pattern _ toString constructor) as fullHandler) =
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
                                    |> Maybe.map (DataSource.map (encodeStaticFileBody >> Just))
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
        , kind = "prerender"
        }


{-| -}
type alias ApiRouteBuilder a constructor =
    Internal.ApiRoute.ApiRouteBuilder a constructor


{-| -}
type alias Response =
    Json.Encode.Value


{-| -}
succeed : a -> ApiRouteBuilder a (List String)
succeed a =
    ApiRouteBuilder Pattern.empty "" (\_ -> a) (\_ -> "") (\list -> list)


{-| Turn the route into a pattern in JSON format. For internal uses.
-}
toJson : ApiRoute response -> Json.Encode.Value
toJson ((ApiRoute { kind }) as apiRoute) =
    Json.Encode.object
        [ ( "pathPattern", apiRoute |> Internal.ApiRoute.toPattern |> Pattern.toJson )
        , ( "kind", Json.Encode.string kind )
        ]


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


{-| For internal use by generated code. Not so useful in user-land.
-}
getBuildTimeRoutes : ApiRoute response -> DataSource (List String)
getBuildTimeRoutes (ApiRoute handler) =
    handler.buildTimeRoutes



--captureRest : ApiRouteBuilder (List String -> a) b -> ApiRouteBuilder a b
--captureRest previousHandler =
--    Debug.todo ""
