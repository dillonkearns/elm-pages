module Template exposing (..)

import Global
import Head
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp


simpler :
    { view :
        (templateMsg -> msg)
        -> (Global.Msg -> msg)
        -> List ( PagePath pathKey, globalMetadata )
        -> templateModel
        -> templateMetadata
        -> renderedTemplate
        -> templateView
    , head :
        PagePath pathKey
        -> templateMetadata
        -> List (Head.Tag pathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg )
    }
    -> Template pathKey templateMetadata renderedTemplate () templateModel templateView templateMsg globalMetadata msg
simpler config =
    template
        { view =
            \toMsg toGlobalMsg allMetadata static model blogPost rendered ->
                config.view toMsg toGlobalMsg allMetadata model blogPost rendered
        , head = \() -> config.head
        , staticData = \_ -> StaticHttp.succeed ()
        , init = config.init
        , update = config.update
        }


template :
    { staticData :
        List ( PagePath pathKey, globalMetadata )
        -> StaticHttp.Request templateStaticData
    , view :
        (templateMsg -> msg)
        -> (Global.Msg -> msg)
        -> List ( PagePath pathKey, globalMetadata )
        -> templateStaticData
        -> templateModel
        -> templateMetadata
        -> renderedTemplate
        -> templateView
    , head :
        templateStaticData
        -> PagePath pathKey
        -> templateMetadata
        -> List (Head.Tag pathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg )
    }
    -> Template pathKey templateMetadata renderedTemplate templateStaticData templateModel templateView templateMsg globalMetadata msg
template config =
    config


type alias Template pathKey templateMetadata renderedTemplate templateStaticData templateModel templateView templateMsg globalMetadata msg =
    { staticData :
        List ( PagePath pathKey, globalMetadata )
        -> StaticHttp.Request templateStaticData
    , view :
        (templateMsg -> msg)
        -> (Global.Msg -> msg)
        -> List ( PagePath pathKey, globalMetadata )
        -> templateStaticData
        -> templateModel
        -> templateMetadata
        -> renderedTemplate
        -> templateView
    , head :
        templateStaticData
        -> PagePath pathKey
        -> templateMetadata
        -> List (Head.Tag pathKey)
    , init : templateMetadata -> ( templateModel, Cmd templateMsg )
    , update : templateMetadata -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg )
    }



--template :
--    { view : StaticData -> Model -> BlogPost -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
--    , head : StaticData -> PagePath Pages.PathKey -> BlogPost -> List (Head.Tag Pages.PathKey)
--    , staticData : b -> StaticHttp.Request StaticData
--    , init : BlogPost -> ( Model, Cmd Msg )
--    , update : BlogPost -> Model -> ( Model, Cmd Msg )
--    }
--template =
--    { view = view
--    , head = head
--    , staticData = staticData
--    , init = init
--    , update = update
--    }
