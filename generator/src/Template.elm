module Template exposing
    ( Builder(..)
    , StaticPayload
    , withStaticData, noStaticData
    , Template, buildNoState
    , TemplateWithState, buildWithLocalState, buildWithSharedState
    , DynamicContext
    )

{-|


## Building a Template

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
  - `static` - this is the static data for this specific page. If you use `noStaticData`, then this will be `()`, meaning there is no page-specific static data.

@docs withStaticData, noStaticData


## Stateless Templates

@docs Template, buildNoState


## Stateful Templates

@docs TemplateWithState, buildWithLocalState, buildWithSharedState

-}

import Browser.Navigation
import Document exposing (Document)
import Head
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared


{-| -}
type alias TemplateWithState routeParams templateStaticData templateModel templateMsg =
    { staticData : routeParams -> StaticHttp.Request templateStaticData
    , staticRoutes : StaticHttp.Request (List routeParams)
    , view :
        templateModel
        -> Shared.Model
        -> StaticPayload templateStaticData routeParams
        -> Document templateMsg
    , head :
        StaticPayload templateStaticData routeParams
        -> List Head.Tag
    , init : routeParams -> ( templateModel, Cmd templateMsg )
    , update : templateStaticData -> Maybe Browser.Navigation.Key -> routeParams -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Maybe Shared.SharedMsg )
    , subscriptions : routeParams -> PagePath -> templateModel -> Shared.Model -> Sub templateMsg
    }


{-| -}
type alias Template routeParams staticData =
    TemplateWithState routeParams staticData () Never


{-| -}
type alias StaticPayload staticData routeParams =
    { static : staticData -- local
    , sharedStatic : Shared.StaticData -- share
    , routeParams : routeParams
    , path : PagePath
    }


{-| -}
type Builder routeParams templateStaticData
    = WithStaticData
        { staticData : routeParams -> StaticHttp.Request templateStaticData
        , staticRoutes : StaticHttp.Request (List routeParams)
        , head :
            StaticPayload templateStaticData routeParams
            -> List Head.Tag
        }


{-| -}
buildNoState :
    { view :
        StaticPayload templateStaticData routeParams
        -> Document Never
    }
    -> Builder routeParams templateStaticData
    -> TemplateWithState routeParams templateStaticData () Never
buildNoState { view } builderState =
    case builderState of
        WithStaticData record ->
            { view = \() _ -> view
            , head = record.head
            , staticData = record.staticData
            , staticRoutes = record.staticRoutes
            , init = \_ -> ( (), Cmd.none )
            , update = \_ _ _ _ _ _ -> ( (), Cmd.none, Nothing )
            , subscriptions = \_ _ _ _ -> Sub.none
            }


{-| -}
buildWithLocalState :
    { view :
        templateModel
        -> Shared.Model
        -> StaticPayload templateStaticData routeParams
        -> Document templateMsg
    , init : routeParams -> ( templateModel, Cmd templateMsg )
    , update : DynamicContext Shared.Model -> templateStaticData -> routeParams -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg )
    , subscriptions : routeParams -> PagePath -> templateModel -> Sub templateMsg
    }
    -> Builder routeParams templateStaticData
    -> TemplateWithState routeParams templateStaticData templateModel templateMsg
buildWithLocalState config builderState =
    case builderState of
        WithStaticData record ->
            { view =
                \model sharedModel staticPayload ->
                    config.view model sharedModel staticPayload
            , head = record.head
            , staticData = record.staticData
            , staticRoutes = record.staticRoutes
            , init = config.init
            , update =
                \staticData navigationKey routeParams msg templateModel sharedModel ->
                    let
                        ( updatedModel, cmd ) =
                            config.update
                                { navigationKey = navigationKey
                                , sharedModel = sharedModel
                                }
                                staticData
                                routeParams
                                msg
                                templateModel
                    in
                    ( updatedModel, cmd, Nothing )
            , subscriptions =
                \routeParams path templateModel sharedModel ->
                    config.subscriptions routeParams path templateModel
            }


type alias DynamicContext shared =
    { navigationKey : Maybe Browser.Navigation.Key
    , sharedModel : shared
    }


{-| -}
buildWithSharedState :
    { view :
        templateModel
        -> Shared.Model
        -> StaticPayload templateStaticData routeParams
        -> Document templateMsg
    , init : routeParams -> ( templateModel, Cmd templateMsg )
    , update : DynamicContext Shared.Model -> routeParams -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg, Maybe Shared.SharedMsg )
    , subscriptions : routeParams -> PagePath -> templateModel -> Shared.Model -> Sub templateMsg
    }
    -> Builder routeParams templateStaticData
    -> TemplateWithState routeParams templateStaticData templateModel templateMsg
buildWithSharedState config builderState =
    case builderState of
        WithStaticData record ->
            { view = config.view
            , head = record.head
            , staticData = record.staticData
            , staticRoutes = record.staticRoutes
            , init = config.init
            , update =
                \pageStaticData navigationKey routeParams msg templateModel sharedModel ->
                    config.update
                        { navigationKey = navigationKey
                        , sharedModel = sharedModel
                        }
                        routeParams
                        msg
                        templateModel
            , subscriptions = config.subscriptions
            }


{-| -}
withStaticData :
    { staticData : routeParams -> StaticHttp.Request templateStaticData
    , staticRoutes : StaticHttp.Request (List routeParams)
    , head : StaticPayload templateStaticData routeParams -> List Head.Tag
    }
    -> Builder routeParams templateStaticData
withStaticData { staticData, head, staticRoutes } =
    WithStaticData
        { staticData = staticData
        , staticRoutes = staticRoutes
        , head = head
        }


{-| -}
noStaticData :
    { head : StaticPayload () routeParams -> List Head.Tag
    , staticRoutes : StaticHttp.Request (List routeParams)
    }
    -> Builder routeParams ()
noStaticData { head, staticRoutes } =
    WithStaticData
        { staticData = \_ -> StaticHttp.succeed ()
        , staticRoutes = staticRoutes
        , head = head
        }
