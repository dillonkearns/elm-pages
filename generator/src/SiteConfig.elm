module SiteConfig exposing (SiteConfig)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head


type alias SiteConfig =
    { canonicalUrl : String
    , head : BackendTask FatalError (List Head.Tag)
    }
