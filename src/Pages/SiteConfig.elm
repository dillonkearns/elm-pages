module Pages.SiteConfig exposing (SiteConfig)

import DataSource exposing (DataSource)
import Head


type alias SiteConfig data =
    { data : DataSource data
    , canonicalUrl : String
    , head : data -> List Head.Tag
    }
