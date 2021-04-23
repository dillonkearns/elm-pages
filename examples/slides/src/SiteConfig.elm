module SiteConfig exposing (SiteConfig)

import Pages.SiteConfig
import Route exposing (Route)


type alias SiteConfig data =
    Pages.SiteConfig.SiteConfig (Maybe Route) data
