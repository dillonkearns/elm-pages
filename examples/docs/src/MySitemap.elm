module MySitemap exposing (install)

import DataSource
import Head
import Pages.Platform exposing (Builder)
import Sitemap


install :
    { siteUrl : String
    }
    -> (List item -> List { path : String, lastMod : Maybe String })
    -> DataSource.DataSource (List item)
    -> Builder pathKey userModel userMsg route
    -> Builder pathKey userModel userMsg route
install config toSitemapEntry request builder =
    builder
        |> Pages.Platform.withGlobalHeadTags [ Head.sitemapLink "/sitemap.xml" ]
        |> Pages.Platform.withFileGenerator
            (request
                |> DataSource.map
                    (\items ->
                        [ Ok
                            { path = [ "sitemap.xml" ]
                            , content = Sitemap.build config (toSitemapEntry items)
                            }
                        ]
                    )
            )
