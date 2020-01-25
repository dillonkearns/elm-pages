module MySitemap exposing (..)

import Dict
import Metadata exposing (Metadata(..))
import Pages
import Pages.PagePath as PagePath exposing (PagePath)
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
            , body : String
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
                        { path = PagePath.toString page.path, lastMod = Nothing }
                    )
            )
    }
