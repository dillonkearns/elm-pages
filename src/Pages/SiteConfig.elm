module Pages.SiteConfig exposing (SiteConfig)

import BackendTask exposing (BackendTask)
import Exception exposing (Throwable)
import Head


type alias SiteConfig =
    { canonicalUrl : String
    , head : BackendTask Throwable (List Head.Tag)
    }
