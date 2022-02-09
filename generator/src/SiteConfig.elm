module SiteConfig exposing (SiteConfig)

import DataSource exposing (DataSource)
import Head
import Route exposing (Route)


type alias SiteConfig data =
    { data : DataSource data
    , canonicalUrl : String
    , head : data -> List Head.Tag
    }
