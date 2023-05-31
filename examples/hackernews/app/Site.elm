module Site exposing (canonicalUrl, config)

import BackendTask exposing (BackendTask)
import Head
import SiteConfig exposing (SiteConfig)


config : SiteConfig
config =
    { canonicalUrl = canonicalUrl
    , head = head
    }


canonicalUrl : String
canonicalUrl =
    "https://hacker-news-elm-pages.netlify.app"


head : BackendTask (List Head.Tag)
head =
    [ Head.metaName "viewport" (Head.raw "width=device-width,initial-scale=1")
    , Head.metaName "mobile-web-app-capable" (Head.raw "yes")
    , Head.metaName "theme-color" (Head.raw "#ffffff")
    , Head.metaName "apple-mobile-web-app-capable" (Head.raw "yes")
    , Head.metaName "apple-mobile-web-app-status-bar-style" (Head.raw "black-translucent")
    ]
        |> BackendTask.succeed
