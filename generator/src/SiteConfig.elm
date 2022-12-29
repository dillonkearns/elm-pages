module SiteConfig exposing (SiteConfig)

import DataSource exposing (DataSource)
import Exception exposing (Throwable)
import Head


type alias SiteConfig =
    { canonicalUrl : String
    , head : DataSource Throwable (List Head.Tag)
    }
