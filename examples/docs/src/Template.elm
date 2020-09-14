module Template exposing (..)

import GlobalMetadata
import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared


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
        }


simpler :
    { view :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
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
        }


stateless :
    { staticData :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> StaticHttp.Request templateStaticData
    , view :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
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
        }


application :
    { staticData :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> StaticHttp.Request templateStaticData
    , view :
        DynamicPayload templateModel
        -> List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateMetadata templateStaticData
        -> List (Head.Tag Pages.PathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> DynamicPayload templateModel -> ( templateModel, Cmd templateMsg, Shared.SharedMsg )
    }
    -> Template templateMetadata templateStaticData templateModel templateMsg
application config =
    { view = config.view
    , head = config.head
    , staticData = config.staticData
    , init = config.init
    , update = config.update
    }


type alias Template templateMetadata templateStaticData templateModel templateMsg =
    { staticData :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> StaticHttp.Request templateStaticData
    , view :
        DynamicPayload templateModel
        -> List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> StaticPayload templateMetadata templateStaticData
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateMetadata templateStaticData
        -> List (Head.Tag Pages.PathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> DynamicPayload templateModel -> ( templateModel, Cmd templateMsg, Shared.SharedMsg )
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
