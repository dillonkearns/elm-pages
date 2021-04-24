module Page exposing
    ( Builder(..)
    , StaticPayload
    , prerenderedRoute, singleRoute, serverlessRoute
    , Page, buildNoState
    , PageWithState, buildWithLocalState, buildWithSharedState
    , DynamicContext
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

@docs prerenderedRoute, singleRoute, serverlessRoute


## Stateless Page Modules

@docs Page, buildNoState


## Stateful Page Modules

@docs PageWithState, buildWithLocalState, buildWithSharedState

-}

import Browser.Navigation
import DataSource exposing (DataSource)
import Document exposing (Document)
import Head
import Pages.PagePath exposing (PagePath)
import ServerRequest exposing (ServerRequest)
import Shared


{-| -}
type alias PageWithState routeParams templateData templateModel templateMsg =
    { data : routeParams -> DataSource templateData
    , staticRoutes : DataSource (List routeParams)
    , view :
        templateModel
        -> Shared.Model
        -> StaticPayload templateData routeParams
        -> Document templateMsg
    , head :
        StaticPayload templateData routeParams
        -> List Head.Tag
    , init : StaticPayload templateData routeParams -> ( templateModel, Cmd templateMsg )
    , update : StaticPayload templateData routeParams -> Maybe Browser.Navigation.Key -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Maybe Shared.SharedMsg )
    , subscriptions : routeParams -> PagePath -> templateModel -> Shared.Model -> Sub templateMsg
    , handleRoute : Maybe (routeParams -> DataSource Bool)
    }


{-| -}
type alias Page routeParams data =
    PageWithState routeParams data () Never


{-| -}
type alias StaticPayload data routeParams =
    { static : data -- local
    , sharedStatic : Shared.Data -- share
    , routeParams : routeParams
    , path : PagePath
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
        , handleRoute : Maybe (routeParams -> DataSource Bool)
        }


{-| -}
buildNoState :
    { view :
        StaticPayload templateData routeParams
        -> Document Never
    }
    -> Builder routeParams templateData
    -> PageWithState routeParams templateData () Never
buildNoState { view } builderState =
    case builderState of
        WithData record ->
            { view = \() _ -> view
            , head = record.head
            , data = record.data
            , staticRoutes = record.staticRoutes
            , init = \_ -> ( (), Cmd.none )
            , update = \_ _ _ _ _ -> ( (), Cmd.none, Nothing )
            , subscriptions = \_ _ _ _ -> Sub.none
            , handleRoute = record.handleRoute
            }


{-| -}
buildWithLocalState :
    { view :
        templateModel
        -> Shared.Model
        -> StaticPayload templateData routeParams
        -> Document templateMsg
    , init : StaticPayload templateData routeParams -> ( templateModel, Cmd templateMsg )
    , update : DynamicContext Shared.Model -> StaticPayload templateData routeParams -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg )
    , subscriptions : routeParams -> PagePath -> templateModel -> Sub templateMsg
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
                \staticPayload navigationKey msg templateModel sharedModel ->
                    let
                        ( updatedModel, cmd ) =
                            config.update
                                { navigationKey = navigationKey
                                , sharedModel = sharedModel
                                }
                                staticPayload
                                msg
                                templateModel
                    in
                    ( updatedModel, cmd, Nothing )
            , subscriptions =
                \routeParams path templateModel sharedModel ->
                    config.subscriptions routeParams path templateModel
            , handleRoute = record.handleRoute
            }


{-| -}
type alias DynamicContext shared =
    { navigationKey : Maybe Browser.Navigation.Key
    , sharedModel : shared
    }


{-| -}
buildWithSharedState :
    { view :
        templateModel
        -> Shared.Model
        -> StaticPayload templateData routeParams
        -> Document templateMsg
    , init : StaticPayload templateData routeParams -> ( templateModel, Cmd templateMsg )
    , update : DynamicContext Shared.Model -> StaticPayload templateData routeParams -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg, Maybe Shared.SharedMsg )
    , subscriptions : routeParams -> PagePath -> templateModel -> Shared.Model -> Sub templateMsg
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
                \staticPayload navigationKey msg templateModel sharedModel ->
                    config.update
                        { navigationKey = navigationKey
                        , sharedModel = sharedModel
                        }
                        staticPayload
                        msg
                        templateModel
            , subscriptions = config.subscriptions
            , handleRoute = record.handleRoute
            }


singleRoute :
    { data : DataSource data
    , head : StaticPayload data {} -> List Head.Tag
    }
    -> Builder {} data
singleRoute { data, head } =
    WithData
        { data = \_ -> data
        , staticRoutes = DataSource.succeed [ {} ]
        , head = head
        , serverless = False
        , handleRoute = Nothing
        }


prerenderedRoute :
    { data : routeParams -> DataSource data
    , routes : DataSource (List routeParams)
    , head : StaticPayload data routeParams -> List Head.Tag
    }
    -> Builder routeParams data
prerenderedRoute { data, head, routes } =
    WithData
        { data = data
        , staticRoutes = routes
        , head = head
        , serverless = False
        , handleRoute = Nothing
        }


{-| -}
serverlessRoute :
    { data : (ServerRequest decodedRequest -> DataSource decodedRequest) -> routeParams -> DataSource data
    , routeFound : routeParams -> DataSource Bool
    , head : StaticPayload data routeParams -> List Head.Tag
    }
    -> Builder routeParams data
serverlessRoute { data, head, routeFound } =
    WithData
        { data = data ServerRequest.toStaticHttp
        , staticRoutes = DataSource.succeed []
        , head = head
        , serverless = True
        , handleRoute = Just routeFound
        }


type RouteFound
    = Found
      -- TODO other status codes, like 403?
    | NotFound404
