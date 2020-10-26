module Template exposing
    ( Builder(..)
    , StaticPayload
    , withStaticData, noStaticData
    , Template, buildNoState
    , TemplateWithState, buildWithLocalState, buildWithSharedState
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

import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared
import TemplateType exposing (TemplateType)


{-| -}
type alias TemplateWithState templateMetadata templateStaticData templateModel templateMsg =
    { staticData :
        List ( PagePath Pages.PathKey, TemplateType )
        -> StaticHttp.Request templateStaticData
    , view :
        templateModel
        -> Shared.Model
        -> List ( PagePath Pages.PathKey, TemplateType )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateMetadata templateStaticData
        -> List (Head.Tag Pages.PathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Maybe Shared.SharedMsg )
    , subscriptions : templateMetadata -> PagePath Pages.PathKey -> templateModel -> Shared.Model -> Sub templateMsg
    }


{-| -}
type alias Template templateMetadata staticData =
    TemplateWithState templateMetadata staticData () Never


{-| -}
type alias StaticPayload metadata staticData =
    { static : staticData -- local
    , sharedStatic : Shared.StaticData -- share
    , metadata : metadata
    , path : PagePath Pages.PathKey
    }


{-| -}
type Builder templateMetadata templateStaticData
    = WithStaticData
        { staticData :
            List ( PagePath Pages.PathKey, TemplateType )
            -> StaticHttp.Request templateStaticData
        , head :
            StaticPayload templateMetadata templateStaticData
            -> List (Head.Tag Pages.PathKey)
        }


{-| -}
buildNoState :
    { view :
        List ( PagePath Pages.PathKey, TemplateType )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView Never
    }
    -> Builder templateMetadata templateStaticData
    -> TemplateWithState templateMetadata templateStaticData () Never
buildNoState { view } builderState =
    case builderState of
        WithStaticData record ->
            { view = \() _ -> view
            , head = record.head
            , staticData = record.staticData
            , init = \_ -> ( (), Cmd.none )
            , update = \_ _ _ _ -> ( (), Cmd.none, Nothing )
            , subscriptions = \_ _ _ _ -> Sub.none
            }


{-| -}
buildWithLocalState :
    { view :
        templateModel
        -> List ( PagePath Pages.PathKey, TemplateType )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg )
    , subscriptions : templateMetadata -> PagePath Pages.PathKey -> templateModel -> Sub templateMsg
    }
    -> Builder templateMetadata templateStaticData
    -> TemplateWithState templateMetadata templateStaticData templateModel templateMsg
buildWithLocalState config builderState =
    case builderState of
        WithStaticData record ->
            { view =
                \model sharedModel allMetadata staticPayload rendered ->
                    config.view model allMetadata staticPayload rendered
            , head = record.head
            , staticData = record.staticData
            , init = config.init
            , update =
                \metadata msg templateModel sharedModel_ ->
                    let
                        ( updatedModel, cmd ) =
                            config.update metadata msg templateModel
                    in
                    ( updatedModel, cmd, Nothing )
            , subscriptions =
                \templateMetadata path templateModel sharedModel ->
                    config.subscriptions templateMetadata path templateModel
            }


{-| -}
buildWithSharedState :
    { view :
        templateModel
        -> Shared.Model
        -> List ( PagePath Pages.PathKey, TemplateType )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Maybe Shared.SharedMsg )
    , subscriptions : templateMetadata -> PagePath Pages.PathKey -> templateModel -> Shared.Model -> Sub templateMsg
    }
    -> Builder templateMetadata templateStaticData
    -> TemplateWithState templateMetadata templateStaticData templateModel templateMsg
buildWithSharedState config builderState =
    case builderState of
        WithStaticData record ->
            { view = config.view
            , head = record.head
            , staticData = record.staticData
            , init = config.init
            , update = config.update
            , subscriptions = config.subscriptions
            }


{-| -}
withStaticData :
    { staticData : List ( PagePath Pages.PathKey, TemplateType ) -> StaticHttp.Request templateStaticData
    , head : StaticPayload templateMetadata templateStaticData -> List (Head.Tag Pages.PathKey)
    }
    -> Builder templateMetadata templateStaticData
withStaticData { staticData, head } =
    WithStaticData
        { staticData = staticData
        , head = head
        }


{-| -}
noStaticData :
    { head : StaticPayload templateMetadata () -> List (Head.Tag Pages.PathKey) }
    -> Builder templateMetadata ()
noStaticData { head } =
    WithStaticData
        { staticData = \_ -> StaticHttp.succeed ()
        , head = head
        }
