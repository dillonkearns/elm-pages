module MySitemap exposing (..)

import Dict
import Metadata exposing (Metadata(..))
import Pages
import Pages.PagePath as PagePath exposing (PagePath)
import RssFeed
import Sitemap
import Time
import Xml
import Xml.Encode exposing (..)


build :
    { siteUrl : String
    }
    ->
        List
            { path : PagePath Pages.PathKey
            , frontmatter : Metadata
            }
    ->
        { path : List String
        , content : String
        }
build config siteMetadata =
    { path = [ "sitemap.xml" ]
    , content =
        Sitemap.build config
            (siteMetadata
                |> List.map
                    (\page ->
                        page.path
                            |> PagePath.toString
                    )
            )
    }
