module Template exposing (..)

import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Shared
import TemplateType exposing (TemplateType)


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
            \model sharedModel allMetadata staticPayload rendered ->
                config.view staticPayload.metadata staticPayload.path rendered
        , head = \staticPayload -> config.head staticPayload.metadata staticPayload.path
        , staticData = \_ -> StaticHttp.succeed ()
        , init = \_ -> ( (), Cmd.none )
        , update = \_ _ _ _ -> ( (), Cmd.none, Shared.NoOp )
        , subscriptions = \_ _ _ _ -> Sub.none
        }


simpler :
    { view :
        List ( PagePath Pages.PathKey, TemplateType )
        -> StaticPayload templateMetadata ()
        -> templateModel
        -> Shared.RenderedBody
        -> Shared.PageView templateMsg
    , head :
        StaticPayload templateMetadata ()
        -> List (Head.Tag Pages.PathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> templateModel -> Shared.Model -> ( templateModel, Cmd templateMsg )
    }
    -> Template templateMetadata () templateModel templateMsg
simpler config =
    application
        { view =
            \model sharedModel allMetadata staticPayload rendered ->
                config.view allMetadata staticPayload model rendered
        , head = config.head
        , staticData = \_ -> StaticHttp.succeed ()
        , init = config.init
        , update = \a1 b1 c1 d1 -> config.update a1 b1 c1 d1 |> (\( a, b ) -> ( a, b, Shared.NoOp ))
        , subscriptions = \_ _ _ _ -> Sub.none
        }


{-| Basic `staticData` (including access to Shared static data)
-}
stateless :
    { staticData :
        List ( PagePath Pages.PathKey, TemplateType )
        -> StaticHttp.Request templateStaticData
    , view :
        List ( PagePath Pages.PathKey, TemplateType )
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
            \model sharedModel allMetadata staticPayload rendered ->
                config.view allMetadata staticPayload rendered
        , head = config.head
        , staticData = config.staticData
        , init = \_ -> ( (), Cmd.none )
        , update = \_ _ _ _ -> ( (), Cmd.none, Shared.NoOp )
        , subscriptions = \_ _ _ _ -> Sub.none
        }


{-| Full application (including local `Model`, `Msg`, `update`)
-}
application :
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


type alias TemplateSandbox templateMetadata =
    Template templateMetadata () () Never


type alias StaticPayload metadata staticData =
    { static : staticData -- local
    , sharedStatic : Shared.StaticData -- share
    , metadata : metadata
    , path : PagePath Pages.PathKey
    }
