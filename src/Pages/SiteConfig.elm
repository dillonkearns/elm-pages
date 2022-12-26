module Pages.SiteConfig exposing (SiteConfig)

import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import Head


type alias SiteConfig =
    { canonicalUrl : String
    , head : DataSource BuildError (List Head.Tag)
    }
