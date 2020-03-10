module MySitemap exposing (..)

import Head
import Metadata exposing (Metadata(..))
import Pages
import Pages.Builder as Builder exposing (Builder)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Sitemap


install :
    { siteUrl : String
    }
    ->
        (List
            { path : PagePath Pages.PathKey
            , frontmatter : Metadata
            , body : String
            }
         -> List { path : String, lastMod : Maybe String }
        )
    -> Builder pathKey userModel userMsg metadata view builderState
    -> Builder pathKey userModel userMsg metadata view builderState
install config toSitemapEntry builder =
    builder
        |> Builder.addGlobalHeadTags [ Head.sitemapLink "/sitemap.xml" ]
        |> Builder.withFileGenerator
            (\siteMetadata ->
                StaticHttp.succeed
                    [ Ok
                        { path = [ "sitemap.xml" ]
                        , content = Sitemap.build config (toSitemapEntry siteMetadata)
                        }
                    ]
            )
