module Template exposing (..)

import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared
import TemplateType


sandbox :
    { view :
        templateMetadata
        -> PagePath Pages.PathKey
        -> Shared.RenderedBody
        -> Shared.PageView Never
    , head :
        templateMetadata
        -> PagePath Pages.PathKey
        -> List (Head.Tag Pages.PathKey)
    }
    -> TemplateSandbox templateMetadata
sandbox config =
    application
        { view =
            \dynamicPayload allMetadata staticPayload rendered ->
                config.view staticPayload.metadata staticPayload.path rendered
        , head = \staticPayload -> config.head staticPayload.metadata staticPayload.path
        , staticData = \_ -> StaticHttp.succeed ()
        , init = \_ -> ( (), Cmd.none )
        , update = \_ _ _ -> ( (), Cmd.none, Shared.NoOp )
        , subscriptions = \_ _ _ -> Sub.none
        }


simpler :
    { view :
        List ( PagePath Pages.PathKey, TemplateType.Metadata )
        -> StaticPayload templateMetadata ()
        -> templateModel
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateMetadata ()
        -> List (Head.Tag Pages.PathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> DynamicPayload templateModel -> ( templateModel, Cmd templateMsg )
    }
    -> Template templateMetadata () templateModel templateMsg
simpler config =
    application
        { view =
            \dynamicPayload allMetadata staticPayload rendered ->
                config.view allMetadata staticPayload dynamicPayload.model rendered
        , head = config.head
        , staticData = \_ -> StaticHttp.succeed ()
        , init = config.init
        , update = \a1 b1 c1 -> config.update a1 b1 c1 |> (\( a, b ) -> ( a, b, Shared.NoOp ))
        , subscriptions = \_ _ _ -> Sub.none
        }


{-| Basic `staticData` (including access to Shared static data)
-}
stateless :
    { staticData :
        List ( PagePath Pages.PathKey, TemplateType.Metadata )
        -> StaticHttp.Request templateStaticData
    , view :
        List ( PagePath Pages.PathKey, TemplateType.Metadata )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateMetadata templateStaticData
        -> List (Head.Tag Pages.PathKey)
    }
    -> Template templateMetadata templateStaticData () templateMsg
stateless config =
    application
        { view =
            \dynamicPayload allMetadata staticPayload rendered ->
                config.view allMetadata staticPayload rendered
        , head = config.head
        , staticData = config.staticData
        , init = \_ -> ( (), Cmd.none )
        , update = \_ _ _ -> ( (), Cmd.none, Shared.NoOp )
        , subscriptions = \_ _ _ -> Sub.none
        }


{-| Full application (including local `Model`, `Msg`, `update`)
-}
application :
    { staticData :
        List ( PagePath Pages.PathKey, TemplateType.Metadata )
        -> StaticHttp.Request templateStaticData
    , view :
        DynamicPayload templateModel
        -> List ( PagePath Pages.PathKey, TemplateType.Metadata )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateMetadata templateStaticData
        -> List (Head.Tag Pages.PathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> DynamicPayload templateModel -> ( templateModel, Cmd templateMsg, Shared.SharedMsg )
    , subscriptions : templateMetadata -> PagePath Pages.PathKey -> DynamicPayload templateModel -> Sub templateMsg
    }
    -> Template templateMetadata templateStaticData templateModel templateMsg
application config =
    { view = config.view
    , head = config.head
    , staticData = config.staticData
    , init = config.init
    , update = config.update
    , subscriptions = config.subscriptions
    }


type alias Template templateMetadata templateStaticData templateModel templateMsg =
    { staticData :
        List ( PagePath Pages.PathKey, TemplateType.Metadata )
        -> StaticHttp.Request templateStaticData
    , view :
        DynamicPayload templateModel
        -> List ( PagePath Pages.PathKey, TemplateType.Metadata )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateMetadata templateStaticData
        -> List (Head.Tag Pages.PathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> DynamicPayload templateModel -> ( templateModel, Cmd templateMsg, Shared.SharedMsg )
    , subscriptions : templateMetadata -> PagePath Pages.PathKey -> DynamicPayload templateModel -> Sub templateMsg
    }


type alias TemplateSandbox templateMetadata =
    Template templateMetadata () () Never


type alias StaticPayload metadata staticData =
    { static : staticData
    , sharedStatic : Shared.StaticData
    , metadata : metadata
    , path : PagePath Pages.PathKey
    }


type alias DynamicPayload model =
    { model : model
    , sharedModel : Shared.Model
    }
