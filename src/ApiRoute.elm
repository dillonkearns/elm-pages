module ApiRoute exposing
    ( ApiRoute, ApiRouteBuilder, Response
    , capture, literal, slash, succeed
    , single, preRender
    , preRenderWithFallback, serverRender
    , withGlobalHeadTags
    , toJson, getBuildTimeRoutes, getGlobalHeadTagsDataSource
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


## Including Head Tags

@docs withGlobalHeadTags


## Internals

@docs toJson, getBuildTimeRoutes, getGlobalHeadTagsDataSource

-}

import DataSource exposing (DataSource)
import DataSource.Http
import Head
import Internal.ApiRoute exposing (ApiRoute(..), ApiRouteBuilder(..))
import Json.Decode as Decode
import Json.Encode
import Pattern
import Regex
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


{-| -}
serverRender : ApiRouteBuilder (Server.Request.Request (DataSource (Server.Response.Response Never))) constructor -> ApiRoute Response
serverRender ((ApiRouteBuilder patterns pattern _ _ _) as fullHandler) =
    ApiRoute
        { regex = Regex.fromString ("^" ++ pattern ++ "$") |> Maybe.withDefault Regex.never
        , matchesToResponse =
            \path ->
                Internal.ApiRoute.tryMatch path fullHandler
                    |> Maybe.map
                        (\toDataSource ->
                            DataSource.Http.get
                                "$$elm-pages$$headers"
                                (Decode.oneOf
                                    [ toDataSource |> Server.Request.getDecoder |> Decode.map Just
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
                                                    |> Server.Response.plainText
                                                    |> Server.Response.withStatusCode 400
                                                    |> DataSource.succeed

                                            Nothing ->
                                                Server.Response.plainText "No matching request handler"
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
        , globalHeadTags = Nothing
        }


{-| -}
preRenderWithFallback : (constructor -> DataSource (List (List String))) -> ApiRouteBuilder (DataSource (Server.Response.Response Never)) constructor -> ApiRoute Response
preRenderWithFallback buildUrls ((ApiRouteBuilder patterns pattern _ toString constructor) as fullHandler) =
    let
        buildTimeRoutes__ : DataSource (List String)
        buildTimeRoutes__ =
            buildUrls (constructor [])
                |> DataSource.map (List.map toString)
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
        , globalHeadTags = Nothing
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
        , globalHeadTags = Nothing
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


withGlobalHeadTags : DataSource (List Head.Tag) -> ApiRoute response -> ApiRoute response
withGlobalHeadTags globalHeadTags (ApiRoute handler) =
    ApiRoute { handler | globalHeadTags = Just globalHeadTags }


getGlobalHeadTagsDataSource : ApiRoute response -> Maybe (DataSource (List Head.Tag))
getGlobalHeadTagsDataSource (ApiRoute handler) =
    handler.globalHeadTags



--captureRest : ApiRouteBuilder (List String -> a) b -> ApiRouteBuilder a b
--captureRest previousHandler =
--    Debug.todo ""
