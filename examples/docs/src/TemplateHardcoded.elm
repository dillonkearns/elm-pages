module TemplateHardcoded exposing (..)

import GlobalMetadata
import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp


template :
    { staticData :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> StaticHttp.Request staticData
    , view :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> staticData
        -> model
        -> metadata
        -> renderedTemplate
        -> view
    , head :
        staticData
        -> PagePath Pages.PathKey
        -> metadata
        -> List (Head.Tag Pages.PathKey)
    , init : metadata -> ( model, Cmd templateMsg )
    , update : metadata -> templateMsg -> model -> ( model, Cmd templateMsg )
    }
    -> Template metadata renderedTemplate staticData model view templateMsg
template config =
    config


type alias Template metadata renderedTemplate staticData model view templateMsg =
    { staticData :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> StaticHttp.Request staticData
    , view :
        List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
        -> staticData
        -> model
        -> metadata
        -> renderedTemplate
        -> view
    , head :
        staticData
        -> PagePath Pages.PathKey
        -> metadata
        -> List (Head.Tag Pages.PathKey)
    , init : metadata -> ( model, Cmd templateMsg )
    , update : metadata -> templateMsg -> model -> ( model, Cmd templateMsg )
    }
