module Template exposing (..)

import Head
import Pages
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp


template :
    { staticData :
        List ( PagePath Pages.PathKey, globalMetadata )
        -> StaticHttp.Request templateStaticData
    , view :
        templateStaticData
        -> templateModel
        -> templateMetadata
        -> renderedTemplate
        -> view
    , head :
        templateStaticData
        -> PagePath Pages.PathKey
        -> templateMetadata
        -> List (Head.Tag Pages.PathKey)
    }
    -> List ( PagePath Pages.PathKey, globalMetadata )
    -> { metadata : templateMetadata, path : PagePath Pages.PathKey }
    ->
        StaticHttp.Request
            { view : templateModel -> renderedTemplate -> view
            , head : List (Head.Tag Pages.PathKey)
            }
template config siteMetadata page =
    config.staticData siteMetadata
        |> StaticHttp.map
            (\staticData ->
                { view =
                    \model rendered ->
                        config.view staticData model page.metadata rendered
                , head = config.head staticData page.path page.metadata
                }
            )
