module Site exposing (config)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import SiteConfig exposing (SiteConfig)


config : SiteConfig
config =
    { canonicalUrl = "https://example.com"
    , head = head
    }


head : BackendTask FatalError (List Head.Tag)
head =
    [ Head.sitemapLink "/sitemap.xml"
    ]
        |> BackendTask.succeed
