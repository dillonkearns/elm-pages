module Template exposing
    ( StaticPayload, Template, TemplateWithState, Template_, buildNoState, buildWithLocalState, buildWithSharedState, noStaticData, withStaticData
    , Builder(..)
    )

{-|

@docs Builder, StaticPayload, Template, TemplateWithState, Template_, buildNoState, buildWithLocalState, buildWithSharedState, noStaticData, withStaticData

-}

import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared
import TemplateType exposing (TemplateType)


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
    -> Template templateMetadata templateStaticData () Never
buildNoState { view } builderState =
    case builderState of
        WithStaticData record ->
            { view = \() _ -> view
            , head = record.head
            , staticData = record.staticData
            , init = \_ -> ( (), Cmd.none )
            , update = \_ _ _ _ -> ( (), Cmd.none, Shared.NoOp )
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
    -> Template templateMetadata templateStaticData templateModel templateMsg
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
                    ( updatedModel, cmd, Shared.NoOp )
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
    , update : templateMetadata -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Shared.SharedMsg )
    , subscriptions : templateMetadata -> PagePath Pages.PathKey -> templateModel -> Shared.Model -> Sub templateMsg
    }
    -> Builder templateMetadata templateStaticData
    -> Template templateMetadata templateStaticData templateModel templateMsg
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


{-| -}
type alias Template templateMetadata templateStaticData templateModel templateMsg =
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
    , update : templateMetadata -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg, Shared.SharedMsg )
    , subscriptions : templateMetadata -> PagePath Pages.PathKey -> templateModel -> Shared.Model -> Sub templateMsg
    }


{-| -}
type alias TemplateWithState templateMetadata templateStaticData templateModel templateMsg =
    Template templateMetadata templateStaticData templateModel templateMsg



--type alias Template_ templateMetadata =
--    Template templateMetadata () () Never


{-| -}
type alias Template_ templateMetadata staticData =
    Template templateMetadata staticData () Never


{-| -}
type alias StaticPayload metadata staticData =
    { static : staticData -- local
    , sharedStatic : Shared.StaticData -- share
    , metadata : metadata
    , path : PagePath Pages.PathKey
    }
