module SiteConfig exposing (SiteConfig)

import DataSource exposing (DataSource)
import Head
import Pages.Manifest
import Route exposing (Route)


type alias SiteConfig data =
    { data : DataSource data
    , canonicalUrl : String
    , manifest : data -> Pages.Manifest.Config
    , head :
        data
        -> List Head.Tag
    }
