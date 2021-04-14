module MySitemap exposing (install)

import Head
import Pages.Platform exposing (Builder)
import Pages.StaticHttp as StaticHttp
import Sitemap


install :
    { siteUrl : String
    }
    -> (List item -> List { path : String, lastMod : Maybe String })
    -> StaticHttp.Request (List item)
    -> Builder pathKey userModel userMsg route
    -> Builder pathKey userModel userMsg route
install config toSitemapEntry request builder =
    builder
        |> Pages.Platform.withGlobalHeadTags [ Head.sitemapLink "/sitemap.xml" ]
        |> Pages.Platform.withFileGenerator
            (request
                |> StaticHttp.map
                    (\items ->
                        [ Ok
                            { path = [ "sitemap.xml" ]
                            , content = Sitemap.build config (toSitemapEntry items)
                            }
                        ]
                    )
            )
