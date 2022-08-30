module Site exposing (canonicalUrl, config)

import DataSource exposing (DataSource)
import Head
import Route
import SiteConfig exposing (SiteConfig)


type alias Data =
    ()


config : SiteConfig
config =
    { canonicalUrl = canonicalUrl
    , head = head
    }


canonicalUrl : String
canonicalUrl =
    "https://elm-pages.com"


head : DataSource Never (List Head.Tag)
head =
    [ Head.sitemapLink "/sitemap.xml"
    ]
        |> DataSource.succeed
