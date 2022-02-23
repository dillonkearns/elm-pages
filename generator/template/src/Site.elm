module Site exposing (config)

import DataSource exposing (DataSource)
import Head
import Pages.Manifest as Manifest
import Route
import SiteConfig exposing (SiteConfig)


type alias Data =
    ()


config : SiteConfig
config =
    { canonicalUrl = "https://elm-pages.com"
    , head = head
    }


head : DataSource (List Head.Tag)
head =
    [ Head.sitemapLink "/sitemap.xml"
    ]
        |> DataSource.succeed


manifest : Data -> Manifest.Config
manifest static =
    Manifest.init
        { name = "Site Name"
        , description = "Description"
        , startUrl = Route.Index |> Route.toPath
        , icons = []
        }
