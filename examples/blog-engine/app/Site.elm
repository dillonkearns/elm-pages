module Site exposing (canonicalUrl, config)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import MimeType
import Pages.Url
import SiteConfig exposing (SiteConfig)


config : SiteConfig
config =
    { canonicalUrl = canonicalUrl
    , head = head
    }


head : BackendTask FatalError (List Head.Tag)
head =
    [ Head.metaName "viewport" (Head.raw "width=device-width,initial-scale=1")
    , Head.metaName "mobile-web-app-capable" (Head.raw "yes")
    , Head.metaName "theme-color" (Head.raw "#ffffff")
    , Head.metaName "apple-mobile-web-app-capable" (Head.raw "yes")
    , Head.metaName "apple-mobile-web-app-status-bar-style" (Head.raw "black-translucent")
    ]
        |> BackendTask.succeed


canonicalUrl : String
canonicalUrl =
    "https://elm-pages.com"
