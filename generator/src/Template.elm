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
import NoMetadata exposing (NoMetadata(..))
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared
import TemplateType exposing (TemplateType)


{-| -}
type alias TemplateWithState templateStaticData templateModel templateMsg =
    { staticData : StaticHttp.Request templateStaticData
    , view :
        templateModel
        -> Shared.Model
        -> StaticPayload templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateStaticData
        -> List (Head.Tag Pages.PathKey)
    , init : NoMetadata -> ( templateModel, Cmd templateMsg )
    , update : NoMetadata -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Maybe Shared.SharedMsg )
    , subscriptions : NoMetadata -> PagePath Pages.PathKey -> templateModel -> Shared.Model -> Sub templateMsg
    }


{-| -}
type alias Template staticData =
    TemplateWithState staticData () Never


{-| -}
type alias StaticPayload staticData =
    { static : staticData -- local
    , sharedStatic : Shared.StaticData -- share
    , path : PagePath Pages.PathKey
    }


{-| -}
type Builder templateMetadata templateStaticData
    = WithStaticData
        { staticData : StaticHttp.Request templateStaticData
        , head :
            StaticPayload templateStaticData
            -> List (Head.Tag Pages.PathKey)
        }


{-| -}
buildNoState :
    { view :
        StaticPayload templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView Never
    }
    -> Builder NoMetadata templateStaticData
    -> TemplateWithState templateStaticData () Never
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
        -> Shared.Model
        -> StaticPayload templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , init : NoMetadata -> ( templateModel, Cmd templateMsg )
    , update : Shared.Model -> NoMetadata -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg )
    , subscriptions : NoMetadata -> PagePath Pages.PathKey -> templateModel -> Sub templateMsg
    }
    -> Builder NoMetadata templateStaticData
    -> TemplateWithState templateStaticData templateModel templateMsg
buildWithLocalState config builderState =
    case builderState of
        WithStaticData record ->
            { view =
                \model sharedModel staticPayload rendered ->
                    config.view model sharedModel staticPayload rendered
            , head = record.head
            , staticData = record.staticData
            , init = config.init
            , update =
                \metadata msg templateModel sharedModel ->
                    let
                        ( updatedModel, cmd ) =
                            config.update sharedModel metadata msg templateModel
                    in
                    ( updatedModel, cmd, Nothing )
            , subscriptions =
                \_ path templateModel sharedModel ->
                    config.subscriptions NoMetadata path templateModel
            }


{-| -}
buildWithSharedState :
    { view :
        templateModel
        -> Shared.Model
        -> StaticPayload templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , init : NoMetadata -> ( templateModel, Cmd templateMsg )
    , update : NoMetadata -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Maybe Shared.SharedMsg )
    , subscriptions : NoMetadata -> PagePath Pages.PathKey -> templateModel -> Shared.Model -> Sub templateMsg
    }
    -> Builder NoMetadata templateStaticData
    -> TemplateWithState templateStaticData templateModel templateMsg
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
    { staticData : StaticHttp.Request templateStaticData
    , head : StaticPayload templateStaticData -> List (Head.Tag Pages.PathKey)
    }
    -> Builder NoMetadata templateStaticData
withStaticData { staticData, head } =
    WithStaticData
        { staticData = staticData
        , head = head
        }


{-| -}
noStaticData :
    { head : StaticPayload () -> List (Head.Tag Pages.PathKey) }
    -> Builder NoMetadata ()
noStaticData { head } =
    WithStaticData
        { staticData = StaticHttp.succeed ()
        , head = head
        }
