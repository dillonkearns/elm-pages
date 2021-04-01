module MySitemap exposing (install)

import Head
import NoMetadata exposing (NoMetadata)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform exposing (Builder)
import Pages.StaticHttp as StaticHttp
import Sitemap


install :
    { siteUrl : String
    }
    ->
        (List
            { path : PagePath pathKey
            , frontmatter : NoMetadata
            , body : String
            }
         -> List { path : String, lastMod : Maybe String }
        )
    -> Builder pathKey userModel userMsg NoMetadata view
    -> Builder pathKey userModel userMsg NoMetadata view
install config toSitemapEntry builder =
    builder
        |> Pages.Platform.withGlobalHeadTags [ Head.sitemapLink "/sitemap.xml" ]
        |> Pages.Platform.withFileGenerator
            (\siteMetadata ->
                StaticHttp.succeed
                    [ Ok
                        { path = [ "sitemap.xml" ]
                        , content = Sitemap.build config (toSitemapEntry siteMetadata)
                        }
                    ]
            )
