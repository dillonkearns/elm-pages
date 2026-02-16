module RouteBuilder exposing
    ( StatelessRoute, buildNoState
    , App
    , withOnAction
    , buildWithLocalState, buildWithSharedState
    , preRender, single
    , preRenderWithFallback, serverRender
    , Builder(..)
    , StatefulRoute
    , StaticPayload
    )

{-|


## Stateless Route Modules

The simplest Route Module you can build is one with no state. It still can use `BackendTask`'s, but it has no `init`, `update`, or `subscriptions`.

It can read the `Shared.Model`, but it cannot send `Shared.Msg`'s to update the `Shared.Model`. If you need a `Model`, use `buildWithLocalState`.

If you need to _change_ Shared state, use `buildWithSharedState`.

@docs StatelessRoute, buildNoState


## Accessing Static Data

With `elm-pages`, you can have HTTP data available before a page is loaded, or read in a file, etc, using the BackendTask API. Since the data
is available when the page is pre-rendered (as well as in the hydrated page), this is called Static Data.

An example of dynamic data would be keyboard input from the user, query params, or any other data that comes from the app running in the browser.

We have the following data during pre-render:

  - `path` - the current path is static. In other words, we know the current path when we build an elm-pages site. Note that we **do not** know query parameters, fragments, etc. That is dynamic data. Pre-rendering occurs for paths in our app, but we don't know what possible query paremters might be used when those paths are hit.
  - `data` - this will be the resolved `BackendTask` for our page.
  - `sharedData` - we can access any shared data between pages. For example, you may have fetched the name of a blog ("Jane's Blog") from the API for a Content Management System (CMS).
  - `routeParams` - this is the record that includes any Dynamic Route Segments for the given page (or an empty record if there are none)

@docs App

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
        BackendTask.succeed
            [ { slug = "blog-post1" }
            , { slug = "blog-post2" }
            ]

@docs preRender, single


## Frozen Views

Use `View.freeze` in your view function to wrap heavy content that should be:

  - Rendered at build time
  - Adopted by the client without re-rendering
  - Eliminated from the client bundle via DCE

Example:

    view app shared =
        { body =
            [ h1 [] [ text app.data.title ]           -- Persistent, sent to client
            , View.freeze (render app.data.content)   -- Ephemeral, DCE'd
            ]
        }

Fields used only inside `View.freeze` calls are automatically detected and
removed from the client-side Data type, enabling dead-code elimination.


## Rendering on the Server

@docs preRenderWithFallback, serverRender


## Internals

@docs Builder
@docs StatefulRoute

-}

import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Form
import Head
import Http
import Pages.ConcurrentSubmission
import Pages.Fetcher
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.RoutePattern exposing (RoutePattern)
import Pages.Navigation
import Pages.PageUrl exposing (PageUrl)
import PagesMsg exposing (PagesMsg)
import Server.Request
import Server.Response
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


{-| -}
type alias StatefulRoute routeParams data action model msg =
    { data : Server.Request.Request -> routeParams -> BackendTask FatalError (Server.Response.Response data ErrorPage)
    , action : Server.Request.Request -> routeParams -> BackendTask FatalError (Server.Response.Response action ErrorPage)
    , staticRoutes : BackendTask FatalError (List routeParams)
    , view :
        Shared.Model
        -> model
        -> App data action routeParams
        -> View (PagesMsg msg)
    , head :
        App data action routeParams
        -> List Head.Tag
    , init : Shared.Model -> App data action routeParams -> ( model, Effect msg )
    , update : App data action routeParams -> msg -> model -> Shared.Model -> ( model, Effect msg, Maybe Shared.Msg )
    , subscriptions : routeParams -> UrlPath -> model -> Shared.Model -> Sub msg
    , handleRoute : { moduleName : List String, routePattern : RoutePattern } -> (routeParams -> List ( String, String )) -> routeParams -> BackendTask FatalError (Maybe NotFoundReason)
    , kind : String
    , onAction : Maybe (action -> msg)
    }


{-| -}
type alias StatelessRoute routeParams data action =
    StatefulRoute routeParams data action {} ()


{-| -}
type alias App data action routeParams =
    { data : data
    , sharedData : Shared.Data
    , routeParams : routeParams
    , path : UrlPath
    , url : Maybe PageUrl
    , action : Maybe action
    , submit :
        { fields : List ( String, String ), headers : List ( String, String ) }
        -> Pages.Fetcher.Fetcher (Result Http.Error action)
    , navigation : Maybe Pages.Navigation.Navigation
    , concurrentSubmissions : Dict String (Pages.ConcurrentSubmission.ConcurrentSubmission (Maybe action))
    , pageFormState : Form.Model
    }


{-| Convenience alias for pages.
-}
type alias StaticPayload data action routeParams =
    App data action routeParams


{-| -}
type Builder routeParams data action
    = WithData
        { data : Server.Request.Request -> routeParams -> BackendTask FatalError (Server.Response.Response data ErrorPage)
        , action : Server.Request.Request -> routeParams -> BackendTask FatalError (Server.Response.Response action ErrorPage)
        , staticRoutes : BackendTask FatalError (List routeParams)
        , head :
            App data action routeParams
            -> List Head.Tag
        , serverless : Bool
        , handleRoute :
            { moduleName : List String, routePattern : RoutePattern }
            -> (routeParams -> List ( String, String ))
            -> routeParams
            -> BackendTask FatalError (Maybe NotFoundReason)
        , kind : String
        }


{-| -}
buildNoState :
    { view :
        App data action routeParams
        -> Shared.Model
        -> View (PagesMsg ())
    }
    -> Builder routeParams data action
    -> StatefulRoute routeParams data action {} ()
buildNoState { view } builderState =
    case builderState of
        WithData record ->
            { view = \shared model app -> view app shared
            , head = record.head
            , data = record.data
            , action = record.action
            , staticRoutes = record.staticRoutes
            , init = \_ _ -> ( {}, Effect.none )
            , update = \_ _ _ _ -> ( {}, Effect.none, Nothing )
            , subscriptions = \_ _ _ _ -> Sub.none
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
        App data action routeParams
        -> Shared.Model
        -> model
        -> View (PagesMsg msg)
    , init : App data action routeParams -> Shared.Model -> ( model, Effect msg )
    , update : App data action routeParams -> Shared.Model -> msg -> model -> ( model, Effect msg )
    , subscriptions : routeParams -> UrlPath -> Shared.Model -> model -> Sub msg
    }
    -> Builder routeParams data action
    -> StatefulRoute routeParams data action model msg
buildWithLocalState config builderState =
    case builderState of
        WithData record ->
            { view =
                \model sharedModel app ->
                    config.view app model sharedModel
            , head = record.head
            , data = record.data
            , action = record.action
            , staticRoutes = record.staticRoutes
            , init = \shared app -> config.init app shared
            , update =
                \app msg model sharedModel ->
                    let
                        ( updatedModel, cmd ) =
                            config.update app sharedModel msg model
                    in
                    ( updatedModel, cmd, Nothing )
            , subscriptions =
                \routeParams path model sharedModel ->
                    config.subscriptions routeParams path sharedModel model
            , handleRoute = record.handleRoute
            , kind = record.kind
            , onAction = Nothing
            }


{-| -}
buildWithSharedState :
    { view :
        App data action routeParams
        -> Shared.Model
        -> model
        -> View (PagesMsg msg)
    , init : App data action routeParams -> Shared.Model -> ( model, Effect msg )
    , update : App data action routeParams -> Shared.Model -> msg -> model -> ( model, Effect msg, Maybe Shared.Msg )
    , subscriptions : routeParams -> UrlPath -> Shared.Model -> model -> Sub msg
    }
    -> Builder routeParams data action
    -> StatefulRoute routeParams data action model msg
buildWithSharedState config builderState =
    case builderState of
        WithData record ->
            { view = \shared model app -> config.view app shared model
            , head = record.head
            , data = record.data
            , action = record.action
            , staticRoutes = record.staticRoutes
            , init = \shared app -> config.init app shared
            , update =
                \app msg model sharedModel ->
                    config.update
                        app
                        sharedModel
                        msg
                        model
            , subscriptions =
                \routeParams path model sharedModel ->
                    config.subscriptions routeParams path sharedModel model
            , handleRoute = record.handleRoute
            , kind = record.kind
            , onAction = Nothing
            }


{-| -}
single :
    { data : BackendTask FatalError data
    , head : App data action {} -> List Head.Tag
    }
    -> Builder {} data action
single { data, head } =
    WithData
        { data = \_ _ -> data |> BackendTask.map Server.Response.render
        , action = \_ _ -> BackendTask.fail (FatalError.fromString "Internal Error - actions should never be called for statically generated pages.")
        , staticRoutes = BackendTask.succeed [ {} ]
        , head = head
        , serverless = False
        , handleRoute = \_ _ _ -> BackendTask.succeed Nothing
        , kind = "static"
        }


{-| -}
preRender :
    { data : routeParams -> BackendTask FatalError data
    , pages : BackendTask FatalError (List routeParams)
    , head : App data action routeParams -> List Head.Tag
    }
    -> Builder routeParams data action
preRender { data, head, pages } =
    WithData
        { data = \_ -> data >> BackendTask.map Server.Response.render
        , action = \_ _ -> BackendTask.fail (FatalError.fromString "Internal Error - actions should never be called for statically generated pages.")
        , staticRoutes = pages
        , head = head
        , serverless = False
        , handleRoute =
            \moduleContext toRecord routeParams ->
                pages
                    |> BackendTask.map
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
    { data : routeParams -> BackendTask FatalError (Server.Response.Response data ErrorPage)
    , pages : BackendTask FatalError (List routeParams)
    , head : App data action routeParams -> List Head.Tag
    }
    -> Builder routeParams data action
preRenderWithFallback { data, head, pages } =
    WithData
        { data = \_ -> data
        , action = \_ _ -> BackendTask.fail (FatalError.fromString "Internal Error - actions should never be called for statically generated pages.")
        , staticRoutes = pages
        , head = head
        , serverless = False
        , handleRoute =
            \moduleContext toRecord routeParams ->
                BackendTask.succeed Nothing
        , kind = "prerender-with-fallback"
        }


{-| -}
serverRender :
    { data : routeParams -> Server.Request.Request -> BackendTask FatalError (Server.Response.Response data ErrorPage)
    , action : routeParams -> Server.Request.Request -> BackendTask FatalError (Server.Response.Response action ErrorPage)
    , head : App data action routeParams -> List Head.Tag
    }
    -> Builder routeParams data action
serverRender { data, action, head } =
    WithData
        { data =
            \request routeParams ->
                data routeParams request
        , action =
            \request routeParams ->
                action routeParams request
        , staticRoutes = BackendTask.succeed []
        , head = head
        , serverless = True
        , handleRoute =
            \moduleContext toRecord routeParams ->
                BackendTask.succeed Nothing
        , kind = "serverless"
        }
