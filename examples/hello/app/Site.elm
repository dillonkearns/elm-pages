module Site exposing (config)

import BackendTask exposing (BackendTask)
import Head
import SiteConfig exposing (SiteConfig)


config : SiteConfig
config =
    { canonicalUrl = "https://elm-pages.com"
    , head = head
    }


head : BackendTask (List Head.Tag)
head =
    [ Head.sitemapLink "/sitemap.xml"
    ]
        |> BackendTask.succeed
