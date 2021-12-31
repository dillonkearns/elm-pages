module Page exposing
    ( Page, buildNoState
    , StaticPayload
    , buildWithLocalState, buildWithSharedState
    , preRender, single
    , preRenderWithFallback, serverRender
    , Builder(..)
    , PageWithState
    )

{-|


## Stateless Page Modules

The simplest Page Module you can build is one with no state. It still can use `DataSource`'s, but it has no `init`, `update`, or `subscriptions`.

It can read the `Shared.Model`, but it cannot send `Shared.Msg`'s to update the `Shared.Model`. If you need a `Model`, use `buildWithLocalState`.

If you need to _change_ Shared state, use `buildWithSharedState`.

@docs Page, buildNoState


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


## Stateful Page Modules

@docs buildWithLocalState, buildWithSharedState


## Pre-Rendered Pages

A `single` page is just a Route that has no Dynamic Route Segments. For example, `Page.About` will have `type alias RouteParams = {}`, whereas `Page.Blog.Slug_` has a Dynamic Segment slug, and `type alias RouteParams = { slug : String }`.

When you run `elm-pages add About`, it will use `Page.single { ... }` because it has empty `RouteParams`. When you run `elm-pages add Blog.Slug_`, will will use `Page.preRender` because it has a Dynamic Route Segment.

So `Page.single` is just a simplified version of `Page.preRender`. If there are no Dynamic Route Segments, then you don't need to define which pages to render so `Page.single` doesn't need a `pages` field.

When there are Dynamic Route Segments, you need to tell `elm-pages` which pages to render. For example:

    page =
        Page.preRender
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
@docs PageWithState

-}

import Browser.Navigation
import DataSource exposing (DataSource)
import DataSource.Http
import Head
import PageServerResponse exposing (PageServerResponse)
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.RoutePattern exposing (RoutePattern)
import Pages.PageUrl exposing (PageUrl)
import Pages.Secrets as Secrets
import Path exposing (Path)
import Server.Request
import Shared
import View exposing (View)


{-| -}
type alias PageWithState routeParams data model msg =
    { data : routeParams -> DataSource (PageServerResponse data)
    , staticRoutes : DataSource (List routeParams)
    , view :
        Maybe PageUrl
        -> Shared.Model
        -> model
        -> StaticPayload data routeParams
        -> View msg
    , head :
        StaticPayload data routeParams
        -> List Head.Tag
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload data routeParams -> ( model, Cmd msg )
    , update : PageUrl -> StaticPayload data routeParams -> Maybe Browser.Navigation.Key -> msg -> model -> Shared.Model -> ( model, Cmd msg, Maybe Shared.Msg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> model -> Shared.Model -> Sub msg
    , handleRoute : { moduleName : List String, routePattern : RoutePattern } -> (routeParams -> List ( String, String )) -> routeParams -> DataSource (Maybe NotFoundReason)
    , kind : String
    }


{-| -}
type alias Page routeParams data =
    PageWithState routeParams data {} Never


{-| -}
type alias StaticPayload data routeParams =
    { data : data
    , sharedData : Shared.Data
    , routeParams : routeParams
    , path : Path
    }


{-| -}
type Builder routeParams data
    = WithData
        { data : routeParams -> DataSource (PageServerResponse data)
        , staticRoutes : DataSource (List routeParams)
        , head :
            StaticPayload data routeParams
            -> List Head.Tag
        , serverless : Bool
        , handleRoute :
            { moduleName : List String, routePattern : RoutePattern }
            -> (routeParams -> List ( String, String ))
            -> routeParams
            -> DataSource (Maybe NotFoundReason)
        , kind : String
        }


{-| -}
buildNoState :
    { view :
        Maybe PageUrl
        -> Shared.Model
        -> StaticPayload data routeParams
        -> View Never
    }
    -> Builder routeParams data
    -> PageWithState routeParams data {} Never
buildNoState { view } builderState =
    case builderState of
        WithData record ->
            { view = \maybePageUrl sharedModel _ -> view maybePageUrl sharedModel
            , head = record.head
            , data = record.data
            , staticRoutes = record.staticRoutes
            , init = \_ _ _ -> ( {}, Cmd.none )
            , update = \_ _ _ _ _ _ -> ( {}, Cmd.none, Nothing )
            , subscriptions = \_ _ _ _ _ -> Sub.none
            , handleRoute = record.handleRoute
            , kind = record.kind
            }


{-| -}
buildWithLocalState :
    { view :
        Maybe PageUrl
        -> Shared.Model
        -> model
        -> StaticPayload data routeParams
        -> View msg
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload data routeParams -> ( model, Cmd msg )
    , update : PageUrl -> Maybe Browser.Navigation.Key -> Shared.Model -> StaticPayload data routeParams -> msg -> model -> ( model, Cmd msg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> Shared.Model -> model -> Sub msg
    }
    -> Builder routeParams data
    -> PageWithState routeParams data model msg
buildWithLocalState config builderState =
    case builderState of
        WithData record ->
            { view =
                \model sharedModel staticPayload ->
                    config.view model sharedModel staticPayload
            , head = record.head
            , data = record.data
            , staticRoutes = record.staticRoutes
            , init = config.init
            , update =
                \pageUrl staticPayload navigationKey msg model sharedModel ->
                    let
                        ( updatedModel, cmd ) =
                            config.update
                                pageUrl
                                navigationKey
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
            }


{-| -}
buildWithSharedState :
    { view :
        Maybe PageUrl
        -> Shared.Model
        -> model
        -> StaticPayload data routeParams
        -> View msg
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload data routeParams -> ( model, Cmd msg )
    , update : PageUrl -> Maybe Browser.Navigation.Key -> Shared.Model -> StaticPayload data routeParams -> msg -> model -> ( model, Cmd msg, Maybe Shared.Msg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> Shared.Model -> model -> Sub msg
    }
    -> Builder routeParams data
    -> PageWithState routeParams data model msg
buildWithSharedState config builderState =
    case builderState of
        WithData record ->
            { view = config.view
            , head = record.head
            , data = record.data
            , staticRoutes = record.staticRoutes
            , init = config.init
            , update =
                \pageUrl staticPayload navigationKey msg model sharedModel ->
                    config.update pageUrl
                        navigationKey
                        sharedModel
                        staticPayload
                        msg
                        model
            , subscriptions =
                \maybePageUrl routeParams path model sharedModel ->
                    config.subscriptions maybePageUrl routeParams path sharedModel model
            , handleRoute = record.handleRoute
            , kind = record.kind
            }


{-| -}
single :
    { data : DataSource data
    , head : StaticPayload data {} -> List Head.Tag
    }
    -> Builder {} data
single { data, head } =
    WithData
        { data = \_ -> data |> DataSource.map PageServerResponse.RenderPage
        , staticRoutes = DataSource.succeed [ {} ]
        , head = head
        , serverless = False
        , handleRoute = \_ _ _ -> DataSource.succeed Nothing
        , kind = "static"
        }


{-| -}
preRender :
    { data : routeParams -> DataSource data
    , pages : DataSource (List routeParams)
    , head : StaticPayload data routeParams -> List Head.Tag
    }
    -> Builder routeParams data
preRender { data, head, pages } =
    WithData
        { data = data >> DataSource.map PageServerResponse.RenderPage
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
    { data : routeParams -> DataSource (PageServerResponse data)
    , pages : DataSource (List routeParams)
    , head : StaticPayload data routeParams -> List Head.Tag
    }
    -> Builder routeParams data
preRenderWithFallback { data, head, pages } =
    WithData
        { data = data
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
    { data : routeParams -> Server.Request.Request (DataSource (PageServerResponse data))
    , head : StaticPayload data routeParams -> List Head.Tag
    }
    -> Builder routeParams data
serverRender { data, head } =
    WithData
        { data =
            \routeParams ->
                DataSource.Http.get
                    (Secrets.succeed "$$elm-pages$$headers")
                    (routeParams
                        |> data
                        |> Server.Request.getDecoder
                    )
                    |> DataSource.andThen
                        (\rendered ->
                            case rendered of
                                Ok okRendered ->
                                    okRendered

                                Err error ->
                                    Server.Request.errorsToString error |> DataSource.fail
                        )
        , staticRoutes = DataSource.succeed []
        , head = head
        , serverless = True
        , handleRoute =
            \moduleContext toRecord routeParams ->
                DataSource.succeed Nothing
        , kind = "serverless"
        }
