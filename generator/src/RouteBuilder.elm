module RouteBuilder exposing
    ( StatelessRoute, buildNoState
    , StaticPayload
    , withOnAction
    , buildWithLocalState, buildWithSharedState
    , preRender, single
    , preRenderWithFallback, serverRender
    , Builder(..)
    , StatefulRoute
    )

{-|


## Stateless Route Modules

The simplest Route Module you can build is one with no state. It still can use `DataSource`'s, but it has no `init`, `update`, or `subscriptions`.

It can read the `Shared.Model`, but it cannot send `Shared.Msg`'s to update the `Shared.Model`. If you need a `Model`, use `buildWithLocalState`.

If you need to _change_ Shared state, use `buildWithSharedState`.

@docs StatelessRoute, buildNoState


## Accessing Static Data

With `elm-pages`, you can have HTTP data available before a page is loaded, or read in a file, etc, using the DataSource API. Since the data
is available when the page is pre-rendered (as well as in the hydrated page), this is called Static Data.

An example of dynamic data would be keyboard input from the user, query params, or any other data that comes from the app running in the browser.

We have the following data during pre-render:

  - `path` - the current path is static. In other words, we know the current path when we build an elm-pages site. Note that we **do not** know query parameters, fragments, etc. That is dynamic data. Pre-rendering occurs for paths in our app, but we don't know what possible query paremters might be used when those paths are hit.
  - `data` - this will be the resolved `DataSource` for our page.
  - `sharedData` - we can access any shared data between pages. For example, you may have fetched the name of a blog ("Jane's Blog") from the API for a Content Management System (CMS).
  - `routeParams` - this is the record that includes any Dynamic Route Segments for the given page (or an empty record if there are none)

@docs StaticPayload

@docs withOnAction


## Stateful Route Modules

@docs buildWithLocalState, buildWithSharedState


## Pre-Rendered Routes

A `single` page is just a Route that has no Dynamic Route Segments. For example, `Route.About` will have `type alias RouteParams = {}`, whereas `Route.Blog.Slug_` has a Dynamic Segment slug, and `type alias RouteParams = { slug : String }`.

When you run `elm-pages add About`, it will use `RouteBuilder.single { ... }` because it has empty `RouteParams`. When you run `elm-pages add Blog.Slug_`, will will use `RouteBuilder.preRender` because it has a Dynamic Route Segment.

So `RouteBuilder.single` is just a simplified version of `RouteBuilder.preRender`. If there are no Dynamic Route Segments, then you don't need to define which pages to render so `RouteBuilder.single` doesn't need a `pages` field.

When there are Dynamic Route Segments, you need to tell `elm-pages` which pages to render. For example:

    page =
        RouteBuilder.preRender
            { data = data
            , pages = pages
            , head = head
            }

    pages =
        DataSource.succeed
            [ { slug = "blog-post1" }
            , { slug = "blog-post2" }
            ]

@docs preRender, single


## Rendering on the Server

@docs preRenderWithFallback, serverRender


## Internals

@docs Builder
@docs StatefulRoute

-}

import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Exception exposing (Throwable)
import Head
import Http
import Json.Decode
import Pages.Fetcher
import Pages.FormState
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.RoutePattern exposing (RoutePattern)
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Transition
import Path exposing (Path)
import Server.Request
import Server.Response
import Shared
import View exposing (View)


{-| -}
type alias StatefulRoute routeParams data action model msg =
    { data : Json.Decode.Value -> routeParams -> DataSource Throwable (Server.Response.Response data ErrorPage)
    , action : Json.Decode.Value -> routeParams -> DataSource Throwable (Server.Response.Response action ErrorPage)
    , staticRoutes : DataSource Throwable (List routeParams)
    , view :
        Maybe PageUrl
        -> Shared.Model
        -> model
        -> StaticPayload data action routeParams
        -> View (Pages.Msg.Msg msg)
    , head :
        StaticPayload data action routeParams
        -> List Head.Tag
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload data action routeParams -> ( model, Effect msg )
    , update : PageUrl -> StaticPayload data action routeParams -> msg -> model -> Shared.Model -> ( model, Effect msg, Maybe Shared.Msg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> model -> Shared.Model -> Sub msg
    , handleRoute : { moduleName : List String, routePattern : RoutePattern } -> (routeParams -> List ( String, String )) -> routeParams -> DataSource Throwable (Maybe NotFoundReason)
    , kind : String
    , onAction : Maybe (action -> msg)
    }


{-| -}
type alias StatelessRoute routeParams data action =
    StatefulRoute routeParams data action {} ()


{-| -}
type alias StaticPayload data action routeParams =
    { data : data
    , sharedData : Shared.Data
    , routeParams : routeParams
    , path : Path
    , action : Maybe action
    , submit :
        { fields : List ( String, String ), headers : List ( String, String ) }
        -> Pages.Fetcher.Fetcher (Result Http.Error action)
    , transition : Maybe Pages.Transition.Transition
    , fetchers : Dict String (Pages.Transition.FetcherState (Maybe action))
    , pageFormState : Pages.FormState.PageFormState
    }


{-| -}
type Builder routeParams data action
    = WithData
        { data : Json.Decode.Value -> routeParams -> DataSource Throwable (Server.Response.Response data ErrorPage)
        , action : Json.Decode.Value -> routeParams -> DataSource Throwable (Server.Response.Response action ErrorPage)
        , staticRoutes : DataSource Throwable (List routeParams)
        , head :
            StaticPayload data action routeParams
            -> List Head.Tag
        , serverless : Bool
        , handleRoute :
            { moduleName : List String, routePattern : RoutePattern }
            -> (routeParams -> List ( String, String ))
            -> routeParams
            -> DataSource Throwable (Maybe NotFoundReason)
        , kind : String
        }


{-| -}
buildNoState :
    { view :
        Maybe PageUrl
        -> Shared.Model
        -> StaticPayload data action routeParams
        -> View (Pages.Msg.Msg ())
    }
    -> Builder routeParams data action
    -> StatefulRoute routeParams data action {} ()
buildNoState { view } builderState =
    case builderState of
        WithData record ->
            { view = \maybePageUrl sharedModel _ -> view maybePageUrl sharedModel
            , head = record.head
            , data = record.data
            , action = record.action
            , staticRoutes = record.staticRoutes
            , init = \_ _ _ -> ( {}, Effect.none )
            , update = \_ _ _ _ _ -> ( {}, Effect.none, Nothing )
            , subscriptions = \_ _ _ _ _ -> Sub.none
            , handleRoute = record.handleRoute
            , kind = record.kind
            , onAction = Nothing
            }


{-| -}
withOnAction : (action -> msg) -> StatefulRoute routeParams data action model msg -> StatefulRoute routeParams data action model msg
withOnAction toMsg config =
    { config
        | onAction = Just toMsg
    }


{-| -}
buildWithLocalState :
    { view :
        Maybe PageUrl
        -> Shared.Model
        -> model
        -> StaticPayload data action routeParams
        -> View (Pages.Msg.Msg msg)
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload data action routeParams -> ( model, Effect msg )
    , update : PageUrl -> Shared.Model -> StaticPayload data action routeParams -> msg -> model -> ( model, Effect msg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> Shared.Model -> model -> Sub msg
    }
    -> Builder routeParams data action
    -> StatefulRoute routeParams data action model msg
buildWithLocalState config builderState =
    case builderState of
        WithData record ->
            { view =
                \model sharedModel staticPayload ->
                    config.view model sharedModel staticPayload
            , head = record.head
            , data = record.data
            , action = record.action
            , staticRoutes = record.staticRoutes
            , init = config.init
            , update =
                \pageUrl staticPayload msg model sharedModel ->
                    let
                        ( updatedModel, cmd ) =
                            config.update
                                pageUrl
                                sharedModel
                                staticPayload
                                msg
                                model
                    in
                    ( updatedModel, cmd, Nothing )
            , subscriptions =
                \maybePageUrl routeParams path model sharedModel ->
                    config.subscriptions maybePageUrl routeParams path sharedModel model
            , handleRoute = record.handleRoute
            , kind = record.kind
            , onAction = Nothing
            }


{-| -}
buildWithSharedState :
    { view :
        Maybe PageUrl
        -> Shared.Model
        -> model
        -> StaticPayload data action routeParams
        -> View (Pages.Msg.Msg msg)
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload data action routeParams -> ( model, Effect msg )
    , update : PageUrl -> Shared.Model -> StaticPayload data action routeParams -> msg -> model -> ( model, Effect msg, Maybe Shared.Msg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> Shared.Model -> model -> Sub msg
    }
    -> Builder routeParams data action
    -> StatefulRoute routeParams data action model msg
buildWithSharedState config builderState =
    case builderState of
        WithData record ->
            { view = config.view
            , head = record.head
            , data = record.data
            , action = record.action
            , staticRoutes = record.staticRoutes
            , init = config.init
            , update =
                \pageUrl staticPayload msg model sharedModel ->
                    config.update pageUrl
                        sharedModel
                        staticPayload
                        msg
                        model
            , subscriptions =
                \maybePageUrl routeParams path model sharedModel ->
                    config.subscriptions maybePageUrl routeParams path sharedModel model
            , handleRoute = record.handleRoute
            , kind = record.kind
            , onAction = Nothing
            }


{-| -}
single :
    { data : DataSource Throwable data
    , head : StaticPayload data action {} -> List Head.Tag
    }
    -> Builder {} data action
single { data, head } =
    WithData
        { data = \_ _ -> data |> DataSource.map Server.Response.render
        , action = \_ _ -> DataSource.fail (Exception.fromString "Internal Error - actions should never be called for statically generated pages.")
        , staticRoutes = DataSource.succeed [ {} ]
        , head = head
        , serverless = False
        , handleRoute = \_ _ _ -> DataSource.succeed Nothing
        , kind = "static"
        }


{-| -}
preRender :
    { data : routeParams -> DataSource Throwable data
    , pages : DataSource Throwable (List routeParams)
    , head : StaticPayload data action routeParams -> List Head.Tag
    }
    -> Builder routeParams data action
preRender { data, head, pages } =
    WithData
        { data = \_ -> data >> DataSource.map Server.Response.render
        , action = \_ _ -> DataSource.fail (Exception.fromString "Internal Error - actions should never be called for statically generated pages.")
        , staticRoutes = pages
        , head = head
        , serverless = False
        , handleRoute =
            \moduleContext toRecord routeParams ->
                pages
                    |> DataSource.map
                        (\allRoutes ->
                            if allRoutes |> List.member routeParams then
                                Nothing

                            else
                                -- TODO pass in toString function, and use a custom one to avoid Debug.toString
                                Just <|
                                    Pages.Internal.NotFoundReason.NotPrerendered
                                        { moduleName = moduleContext.moduleName
                                        , routePattern = moduleContext.routePattern
                                        , matchedRouteParams = toRecord routeParams
                                        }
                                        (allRoutes
                                            |> List.map toRecord
                                        )
                        )
        , kind = "prerender"
        }


{-| -}
preRenderWithFallback :
    { data : routeParams -> DataSource Throwable (Server.Response.Response data ErrorPage)
    , pages : DataSource Throwable (List routeParams)
    , head : StaticPayload data action routeParams -> List Head.Tag
    }
    -> Builder routeParams data action
preRenderWithFallback { data, head, pages } =
    WithData
        { data = \_ -> data
        , action = \_ _ -> DataSource.fail (Exception.fromString "Internal Error - actions should never be called for statically generated pages.")
        , staticRoutes = pages
        , head = head
        , serverless = False
        , handleRoute =
            \moduleContext toRecord routeParams ->
                DataSource.succeed Nothing
        , kind = "prerender-with-fallback"
        }


{-| -}
serverRender :
    { data : routeParams -> Server.Request.Parser (DataSource Throwable (Server.Response.Response data ErrorPage))
    , action : routeParams -> Server.Request.Parser (DataSource Throwable (Server.Response.Response action ErrorPage))
    , head : StaticPayload data action routeParams -> List Head.Tag
    }
    -> Builder routeParams data action
serverRender { data, action, head } =
    WithData
        { data =
            \requestPayload routeParams ->
                (routeParams
                    |> data
                    |> Server.Request.getDecoder
                    |> (\decoder ->
                            Json.Decode.decodeValue decoder requestPayload
                                |> Result.mapError Json.Decode.errorToString
                                |> DataSource.fromResult
                                |> DataSource.onError (\error -> Debug.todo "TODO - handle error type")
                       )
                )
                    |> DataSource.andThen
                        (\rendered ->
                            case rendered of
                                Ok okRendered ->
                                    okRendered

                                Err error ->
                                    Server.Request.errorsToString error
                                        |> Exception.fromString
                                        |> DataSource.fail
                        )
        , action =
            \requestPayload routeParams ->
                (routeParams
                    |> action
                    |> Server.Request.getDecoder
                    |> (\decoder ->
                            Json.Decode.decodeValue decoder requestPayload
                                |> Result.mapError Json.Decode.errorToString
                                |> DataSource.fromResult
                                |> DataSource.onError (\error -> Debug.todo "TODO - handle error type")
                       )
                )
                    |> DataSource.andThen
                        (\rendered ->
                            case rendered of
                                Ok okRendered ->
                                    okRendered

                                Err error ->
                                    Server.Request.errorsToString error
                                        |> Exception.fromString
                                        |> DataSource.fail
                        )
        , staticRoutes = DataSource.succeed []
        , head = head
        , serverless = True
        , handleRoute =
            \moduleContext toRecord routeParams ->
                DataSource.succeed Nothing
        , kind = "serverless"
        }
