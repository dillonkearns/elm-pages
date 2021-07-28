module Page exposing
    ( Builder(..)
    , StaticPayload
    , prerender, prerenderWithFallback, single, serverless
    , Page, buildNoState
    , PageWithState, buildWithLocalState, buildWithSharedState
    )

{-|


## Building a Page Module

@docs Builder


## Static Data

Every template will have access to a `StaticPayload`.

@docs StaticPayload

Since this data is _static_, you have access to it before the user has loaded the page, including at build time.
An example of dynamic data would be keyboard input from the user, query params, or any other data that comes from the app running in the browser.

But before the user even requests the page, we have the following data:

  - `path` - these paths are static. In other words, we know every single path when we build an elm-pages site.
  - `metadata` - we have a decoded Elm value for the page's metadata.
  - `sharedStatic` - we can access any shared data between pages. For example, you may have fetched the name of a blog ("Jane's Blog") from the API for a Content Management System (CMS).
  - `static` - this is the static data for this specific page. If you use `noData`, then this will be `()`, meaning there is no page-specific static data.

@docs prerender, prerenderWithFallback, single, serverless


## Stateless Page Modules

@docs Page, buildNoState


## Stateful Page Modules

@docs PageWithState, buildWithLocalState, buildWithSharedState

-}

import Browser.Navigation
import DataSource exposing (DataSource)
import DataSource.ServerRequest as ServerRequest exposing (ServerRequest)
import Head
import NotFoundReason exposing (NotFoundReason)
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import RoutePattern exposing (RoutePattern)
import Shared
import View exposing (View)


{-| -}
type alias PageWithState routeParams templateData templateModel templateMsg =
    { data : routeParams -> DataSource templateData
    , staticRoutes : DataSource (List routeParams)
    , view :
        Maybe PageUrl
        -> Shared.Model
        -> templateModel
        -> StaticPayload templateData routeParams
        -> View templateMsg
    , head :
        StaticPayload templateData routeParams
        -> List Head.Tag
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload templateData routeParams -> ( templateModel, Cmd templateMsg )
    , update : PageUrl -> StaticPayload templateData routeParams -> Maybe Browser.Navigation.Key -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Maybe Shared.Msg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> templateModel -> Shared.Model -> Sub templateMsg
    , handleRoute : { moduleName : List String, routePattern : RoutePattern } -> (routeParams -> List ( String, String )) -> routeParams -> DataSource (Maybe NotFoundReason)
    , kind : String
    }


{-| -}
type alias Page routeParams data =
    PageWithState routeParams data () Never


{-| -}
type alias StaticPayload data routeParams =
    { data : data
    , sharedData : Shared.Data
    , routeParams : routeParams
    , path : Path
    }


{-| -}
type Builder routeParams templateData
    = WithData
        { data : routeParams -> DataSource templateData
        , staticRoutes : DataSource (List routeParams)
        , head :
            StaticPayload templateData routeParams
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
        -> StaticPayload templateData routeParams
        -> View Never
    }
    -> Builder routeParams templateData
    -> PageWithState routeParams templateData () Never
buildNoState { view } builderState =
    case builderState of
        WithData record ->
            { view = \maybePageUrl sharedModel _ -> view maybePageUrl sharedModel
            , head = record.head
            , data = record.data
            , staticRoutes = record.staticRoutes
            , init = \_ _ _ -> ( (), Cmd.none )
            , update = \_ _ _ _ _ _ -> ( (), Cmd.none, Nothing )
            , subscriptions = \_ _ _ _ _ -> Sub.none
            , handleRoute = record.handleRoute
            , kind = record.kind
            }


{-| -}
buildWithLocalState :
    { view :
        Maybe PageUrl
        -> Shared.Model
        -> templateModel
        -> StaticPayload templateData routeParams
        -> View templateMsg
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload templateData routeParams -> ( templateModel, Cmd templateMsg )
    , update : PageUrl -> Maybe Browser.Navigation.Key -> Shared.Model -> StaticPayload templateData routeParams -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> templateModel -> Sub templateMsg
    }
    -> Builder routeParams templateData
    -> PageWithState routeParams templateData templateModel templateMsg
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
                \pageUrl staticPayload navigationKey msg templateModel sharedModel ->
                    let
                        ( updatedModel, cmd ) =
                            config.update
                                pageUrl
                                navigationKey
                                sharedModel
                                staticPayload
                                msg
                                templateModel
                    in
                    ( updatedModel, cmd, Nothing )
            , subscriptions =
                \maybePageUrl routeParams path templateModel sharedModel ->
                    config.subscriptions maybePageUrl routeParams path templateModel
            , handleRoute = record.handleRoute
            , kind = record.kind
            }


{-| -}
buildWithSharedState :
    { view :
        Maybe PageUrl
        -> Shared.Model
        -> templateModel
        -> StaticPayload templateData routeParams
        -> View templateMsg
    , init : Maybe PageUrl -> Shared.Model -> StaticPayload templateData routeParams -> ( templateModel, Cmd templateMsg )
    , update : PageUrl -> Maybe Browser.Navigation.Key -> Shared.Model -> StaticPayload templateData routeParams -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg, Maybe Shared.Msg )
    , subscriptions : Maybe PageUrl -> routeParams -> Path -> templateModel -> Shared.Model -> Sub templateMsg
    }
    -> Builder routeParams templateData
    -> PageWithState routeParams templateData templateModel templateMsg
buildWithSharedState config builderState =
    case builderState of
        WithData record ->
            { view = config.view
            , head = record.head
            , data = record.data
            , staticRoutes = record.staticRoutes
            , init = config.init
            , update =
                \pageUrl staticPayload navigationKey msg templateModel sharedModel ->
                    config.update pageUrl
                        navigationKey
                        sharedModel
                        staticPayload
                        msg
                        templateModel
            , subscriptions = config.subscriptions
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
        { data = \_ -> data
        , staticRoutes = DataSource.succeed [ {} ]
        , head = head
        , serverless = False
        , handleRoute = \_ _ _ -> DataSource.succeed Nothing
        , kind = "static"
        }


{-| -}
prerender :
    { data : routeParams -> DataSource data
    , routes : DataSource (List routeParams)
    , head : StaticPayload data routeParams -> List Head.Tag
    }
    -> Builder routeParams data
prerender { data, head, routes } =
    WithData
        { data = data
        , staticRoutes = routes
        , head = head
        , serverless = False
        , handleRoute =
            \moduleContext toRecord routeParams ->
                routes
                    |> DataSource.map
                        (\allRoutes ->
                            if allRoutes |> List.member routeParams then
                                Nothing

                            else
                                -- TODO pass in toString function, and use a custom one to avoid Debug.toString
                                Just <|
                                    NotFoundReason.NotPrerendered
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
prerenderWithFallback :
    { data : routeParams -> DataSource data
    , routes : DataSource (List routeParams)
    , handleFallback : routeParams -> DataSource Bool
    , head : StaticPayload data routeParams -> List Head.Tag
    }
    -> Builder routeParams data
prerenderWithFallback { data, head, routes, handleFallback } =
    WithData
        { data = data
        , staticRoutes = routes
        , head = head
        , serverless = False
        , handleRoute =
            \moduleContext toRecord routeParams ->
                handleFallback routeParams
                    |> DataSource.andThen
                        (\handleFallbackResult ->
                            if handleFallbackResult then
                                DataSource.succeed Nothing

                            else
                                -- we want to lazily evaluate this in our on-demand builders
                                -- so we try handle fallback first and short-circuit in those cases
                                -- TODO - we could make an optimization to handle this differently
                                -- between on-demand builders and the dev server
                                -- we only need to match the pre-rendered routes in the dev server,
                                -- not in on-demand builders
                                routes
                                    |> DataSource.map
                                        (\allRoutes ->
                                            if allRoutes |> List.member routeParams then
                                                Nothing

                                            else
                                                Just <|
                                                    NotFoundReason.NotPrerenderedOrHandledByFallback
                                                        { moduleName = moduleContext.moduleName
                                                        , routePattern = moduleContext.routePattern
                                                        , matchedRouteParams = toRecord routeParams
                                                        }
                                                        (allRoutes
                                                            |> List.map toRecord
                                                        )
                                        )
                        )
        , kind = "prerender-with-fallback"
        }


{-| -}
serverless :
    { data : (ServerRequest decodedRequest -> DataSource decodedRequest) -> routeParams -> DataSource data
    , routeFound : routeParams -> DataSource Bool
    , head : StaticPayload data routeParams -> List Head.Tag
    }
    -> Builder routeParams data
serverless { data, head, routeFound } =
    WithData
        { data = data ServerRequest.toStaticHttp
        , staticRoutes = DataSource.succeed []
        , head = head
        , serverless = True
        , handleRoute =
            \moduleContext toRecord routeParams ->
                routeFound routeParams
                    |> DataSource.map
                        (\found ->
                            if found then
                                Nothing

                            else
                                Just
                                    (NotFoundReason.UnhandledServerRoute
                                        { moduleName = moduleContext.moduleName
                                        , routePattern = moduleContext.routePattern
                                        , matchedRouteParams = toRecord routeParams
                                        }
                                    )
                        )
        , kind = "serverless"
        }


{-| -}
type RouteFound
    = Found
      -- TODO other status codes, like 403?
    | NotFound404
