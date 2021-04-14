module SiteConfig exposing (SiteConfig)

import Pages.SiteConfig
import Route exposing (Route)


type alias SiteConfig staticData =
    Pages.SiteConfig.SiteConfig (Maybe Route) staticData
