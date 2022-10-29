module Site exposing (canonicalUrl, config)

import DataSource exposing (DataSource)
import Head
import Route exposing (Route)
import SiteConfig exposing (SiteConfig)
import Sitemap


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


head : DataSource (List Head.Tag)
head =
    [ Head.metaName "viewport" (Head.raw "width=device-width,initial-scale=1")
    , Head.metaName "mobile-web-app-capable" (Head.raw "yes")
    , Head.metaName "theme-color" (Head.raw "#ffffff")
    , Head.metaName "apple-mobile-web-app-capable" (Head.raw "yes")
    , Head.metaName "apple-mobile-web-app-status-bar-style" (Head.raw "black-translucent")
    , Head.sitemapLink "/sitemap.xml"
    ]
        |> DataSource.succeed


siteMap :
    List (Maybe Route)
    -> { path : List String, content : String }
siteMap allRoutes =
    allRoutes
        |> List.filterMap identity
        |> List.map
            (\route ->
                { path = Route.routeToPath route |> String.join "/"
                , lastMod = Nothing
                }
            )
        |> Sitemap.build { siteUrl = "https://elm-pages.com" }
        |> (\sitemapXmlString -> { path = [ "sitemap.xml" ], content = sitemapXmlString })
