module Site exposing (canonicalUrl, config)

import BackendTask exposing (BackendTask)
import Exception exposing (Throwable)
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


head : BackendTask Throwable (List Head.Tag)
head =
    [ Head.sitemapLink "/sitemap.xml"
    ]
        |> BackendTask.succeed


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
