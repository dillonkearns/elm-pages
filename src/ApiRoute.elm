module ApiRoute exposing
    ( single, preRender
    , serverRender
    , preRenderWithFallback
    , ApiRoute, ApiRouteBuilder, Response
    , capture, literal, slash, succeed
    , withGlobalHeadTags
    , toJson, getBuildTimeRoutes, getGlobalHeadTagsDataSource
    )

{-| ApiRoute's are defined in `src/Api.elm` and are a way to generate files, like RSS feeds, sitemaps, or any text-based file that you output with an Elm function! You get access
to a DataSource so you can pull in HTTP data, etc. Because ApiRoutes don't hydrate into Elm apps (like pages in elm-pages do), you can pull in as much data as you want in
the DataSource for your ApiRoutes, and it won't effect the payload size. Instead, the size of an ApiRoute is just the content you output for that route.

Similar to your elm-pages Route Modules, ApiRoute's can be either server-rendered or pre-rendered. Let's compare the differences between pre-rendered and server-rendered ApiRoutes, and the different
use cases they support.


## Pre-Rendering

A pre-rendered ApiRoute is just a generated file. For example:

  - [An RSS feed](https://github.com/dillonkearns/elm-pages/blob/131f7b750cdefb2ba7a34a06be06dfbfafc79a86/examples/docs/app/Api.elm#L77-L84)
  - [A calendar feed in the ical format](https://github.com/dillonkearns/incrementalelm.com/blob/d4934d899d06232dc66dcf9f4b5eccc74bbc60d3/src/Api.elm#L51-L60)
  - A redirect file for a hosting provider like Netlify

You could even generate a JavaScript file, an Elm file, or any file with a String body! It's really just a way to generate files, which are typically used to serve files to a user or Browser, but you execute them, copy them, etc. The only limit is your imagination!
The beauty is that you have a way to 1) pull in type-safe data using DataSource's, and 2) write those files, and all in pure Elm!

@docs single, preRender


## Server Rendering

You could use server-rendered ApiRoutes to do a lot of similar things, the main difference being that it will be served up through a URL and generated on-demand when that URL is requested.
So for example, for an RSS feed or ical calendar feed like in the pre-rendered examples, you could build the same routes, but you would be pulling in the list of posts or calendar events on-demand rather
than upfront at build-time. That means you can hit your database and serve up always-up-to-date data.

Not only that, but your server-rendered ApiRoutes have access to the incoming HTTP request payload just like your server-rendered Route Modules do. Just as with server-rendered Route Modules,
a server-rendered ApiRoute accesses the incoming HTTP request through a [Server.Request.Parser](Server-Request). Consider the use cases that this opens up:

  - Serve up protected assets. For example, gated content, like a paid subscriber feed for a podcast that checks authentication information in a query parameter to authenticate that a user has an active paid subscription before serving up the Pro RSS feed.
  - Serve up user-specific content, either through a cookie or other means of authentication
  - Look at the [accepted content-type in the request headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept) and use that to choose a response format, like XML or JSON ([full example](https://github.com/dillonkearns/elm-pages/blob/131f7b750cdefb2ba7a34a06be06dfbfafc79a86/examples/end-to-end/app/Api.elm#L76-L107)).
  - Look at the [accepted language in the request headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept-Language) and use that to choose a language for the response data.

@docs serverRender

You can also do a hybrid approach using `preRenderWithFallback`. This allows you to pre-render a set of routes at build-time, but build additional routes that weren't rendered at build-time on the fly on the server.
Conceptually, this is just a delayed version of a pre-rendered route. Because of that, you _do not_ have access to the incoming HTTP request (no `Server.Request.Parser` like in server-rendered ApiRoute's).
The strategy used to build these routes will differ depending on your hosting provider and the elm-pages adapter you have setup, but generally ApiRoute's that use `preRenderWithFallback` will be cached on the server
so within a certain time interval (or in the case of [Netlify's DPR](https://www.netlify.com/blog/2021/04/14/distributed-persistent-rendering-a-new-jamstack-approach-for-faster-builds/), until a new build is done)
that asset will be served up if that URL was already served up by the server.

@docs preRenderWithFallback


## Defining ApiRoute's

You define your ApiRoute's in `app/Api.elm`. Here's a simple example:

    module Api exposing (routes)

    import ApiRoute
    import DataSource exposing (DataSource)
    import Server.Request

    routes :
        DataSource (List Route)
        -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
        -> List (ApiRoute.ApiRoute ApiRoute.Response)
    routes getStaticRoutes htmlToString =
        [ preRenderedExample
        , requestPrinterExample
        ]

    {-| Generates the following files when you
    run `elm-pages build`:

      - `dist/users/1.json`
      - `dist/users/2.json`
      - `dist/users/3.json`

    When you host it, these static assets will
    be served at `/users/1.json`, etc.

    -}
    preRenderedExample : ApiRoute.ApiRoute ApiRoute.Response
    preRenderedExample =
        ApiRoute.succeed
            (\userId ->
                DataSource.succeed
                    (Json.Encode.object
                        [ ( "id", Json.Encode.string userId )
                        , ( "name", "Data for user " ++ userId |> Json.Encode.string )
                        ]
                        |> Json.Encode.encode 2
                    )
            )
            |> ApiRoute.literal "users"
            |> ApiRoute.slash
            |> ApiRoute.capture
            |> ApiRoute.literal ".json"
            |> ApiRoute.preRender
                (\route ->
                    DataSource.succeed
                        [ route "1"
                        , route "2"
                        , route "3"
                        ]
                )

    {-| This returns a JSON response that prints information about the incoming
    HTTP request. In practice you'd want to do something useful with that data,
    and use more of the high-level helpers from the Server.Request API.
    -}
    requestPrinterExample : ApiRoute ApiRoute.Response
    requestPrinterExample =
        ApiRoute.succeed
            (Server.Request.map4
                (\rawBody method cookies queryParams ->
                    Encode.object
                        [ ( "rawBody"
                          , rawBody
                                |> Maybe.map Encode.string
                                |> Maybe.withDefault Encode.null
                          )
                        , ( "method"
                          , method
                                |> Server.Request.methodToString
                                |> Encode.string
                          )
                        , ( "cookies"
                          , cookies
                                |> Encode.dict
                                    identity
                                    Encode.string
                          )
                        , ( "queryParams"
                          , queryParams
                                |> Encode.dict
                                    identity
                                    (Encode.list Encode.string)
                          )
                        ]
                        |> Response.json
                        |> DataSource.succeed
                )
                Server.Request.rawBody
                Server.Request.method
                Server.Request.allCookies
                Server.Request.queryParams
            )
            |> ApiRoute.literal "api"
            |> ApiRoute.slash
            |> ApiRoute.literal "request-test"
            |> ApiRoute.serverRender

@docs ApiRoute, ApiRouteBuilder, Response

@docs capture, literal, slash, succeed


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


{-| Same as [`preRender`](#preRender), but for an ApiRoute that has no dynamic segments. This is just a bit simpler because
since there are no dynamic segments, you don't need to provide a DataSource with the list of dynamic segments to pre-render because there is only a single possible route.
-}
single : ApiRouteBuilder (DataSource String) (List String) -> ApiRoute Response
single handler =
    handler
        |> preRender (\constructor -> DataSource.succeed [ constructor ])


{-| -}
serverRender : ApiRouteBuilder (Server.Request.Parser (DataSource (Server.Response.Response Never Never))) constructor -> ApiRoute Response
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
                                (toDataSource |> Server.Request.getDecoder |> Decode.map Just)
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
preRenderWithFallback : (constructor -> DataSource (List (List String))) -> ApiRouteBuilder (DataSource (Server.Response.Response Never Never)) constructor -> ApiRoute Response
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


{-| A literal String segment of a route.
-}
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


{-| Include head tags on every page's HTML.
-}
withGlobalHeadTags : DataSource (List Head.Tag) -> ApiRoute response -> ApiRoute response
withGlobalHeadTags globalHeadTags (ApiRoute handler) =
    ApiRoute { handler | globalHeadTags = Just globalHeadTags }


{-| -}
getGlobalHeadTagsDataSource : ApiRoute response -> Maybe (DataSource (List Head.Tag))
getGlobalHeadTagsDataSource (ApiRoute handler) =
    handler.globalHeadTags



--captureRest : ApiRouteBuilder (List String -> a) b -> ApiRouteBuilder a b
--captureRest previousHandler =
--    Debug.todo ""
