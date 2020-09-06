module Template exposing (..)

import Global
import Head
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp


simplest :
    { view :
        List ( PagePath pathKey, globalMetadata )
        -> ()
        -> templateMetadata
        -> renderedTemplate
        -> templateView
    , head :
        PagePath pathKey
        -> templateMetadata
        -> List (Head.Tag pathKey)
    }
    -> Template pathKey templateMetadata renderedTemplate () () templateView templateMsg globalMetadata
simplest config =
    template
        { view =
            \allMetadata () model blogPost rendered ->
                config.view allMetadata model blogPost rendered
        , head = \() -> config.head
        , staticData = \_ -> StaticHttp.succeed ()
        , init = \_ -> ( (), Cmd.none )
        , update = \_ _ _ -> ( (), Cmd.none )
        , save = \_ globalModel -> globalModel
        , load = \_ model -> ( model, Cmd.none )
        }


simpler :
    { view :
        List ( PagePath pathKey, globalMetadata )
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
    -> Template pathKey templateMetadata renderedTemplate () templateModel templateView templateMsg globalMetadata
simpler config =
    template
        { view =
            \allMetadata () model blogPost rendered ->
                config.view allMetadata model blogPost rendered
        , head = \() -> config.head
        , staticData = \_ -> StaticHttp.succeed ()
        , init = config.init
        , update = config.update
        , save = \_ globalModel -> globalModel
        , load = \_ model -> ( model, Cmd.none )
        }


stateless :
    { staticData :
        List ( PagePath pathKey, globalMetadata )
        -> StaticHttp.Request templateStaticData
    , view :
        List ( PagePath pathKey, globalMetadata )
        -> templateStaticData
        -> templateMetadata
        -> renderedTemplate
        -> templateView
    , head :
        templateStaticData
        -> PagePath pathKey
        -> templateMetadata
        -> List (Head.Tag pathKey)
    }
    -> Template pathKey templateMetadata renderedTemplate templateStaticData () templateView templateMsg globalMetadata
stateless config =
    template
        { view =
            \allMetadata staticData () blogPost rendered ->
                config.view allMetadata staticData blogPost rendered
        , head = config.head
        , staticData = config.staticData
        , init = \_ -> ( (), Cmd.none )
        , update = \_ _ _ -> ( (), Cmd.none )
        , save = \_ globalModel -> globalModel
        , load = \_ model -> ( model, Cmd.none )
        }


template :
    { staticData :
        List ( PagePath pathKey, globalMetadata )
        -> StaticHttp.Request templateStaticData
    , view :
        List ( PagePath pathKey, globalMetadata )
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
    , save : templateModel -> Global.Model -> Global.Model
    , load : Global.Model -> templateModel -> ( templateModel, Cmd templateMsg )
    }
    -> Template pathKey templateMetadata renderedTemplate templateStaticData templateModel templateView templateMsg globalMetadata
template config =
    { view = config.view
    , head = config.head
    , staticData = config.staticData
    , init = config.init
    , update =
        \a b c ->
            config.update a b c
                |> (\tuple ->
                        ( tuple |> Tuple.first, tuple |> Tuple.second, Global.NoOp )
                   )
    , save = \_ globalModel -> globalModel
    , load = \_ model -> ( model, Cmd.none )
    }


type alias Template pathKey templateMetadata renderedTemplate templateStaticData templateModel templateView templateMsg globalMetadata =
    { staticData :
        List ( PagePath pathKey, globalMetadata )
        -> StaticHttp.Request templateStaticData
    , view :
        List ( PagePath pathKey, globalMetadata )
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
    , update : templateMetadata -> templateMsg -> templateModel -> ( templateModel, Cmd templateMsg, Global.GlobalMsg )
    , save : templateModel -> Global.Model -> Global.Model
    , load : Global.Model -> templateModel -> ( templateModel, Cmd templateMsg )
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
