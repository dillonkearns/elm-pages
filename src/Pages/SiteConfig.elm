module Pages.SiteConfig exposing (SiteConfig)

import Head
import Pages.Manifest
import Pages.StaticHttp as StaticHttp


type alias SiteConfig staticData pathKey =
    { staticData : StaticHttp.Request staticData
    , canonicalUrl : staticData -> String
    , manifest : staticData -> Pages.Manifest.Config pathKey
    , head :
        staticData
        -> List (Head.Tag pathKey)
    }
