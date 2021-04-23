module Pages.SiteConfig exposing (SiteConfig)

import DataSource
import Head
import Pages.Manifest


type alias SiteConfig route data =
    List route
    ->
        { data : DataSource.DataSource data
        , canonicalUrl : String
        , manifest : data -> Pages.Manifest.Config
        , head :
            data
            -> List Head.Tag
        , generateFiles :
            DataSource.DataSource
                (List
                    (Result
                        String
                        { path : List String
                        , content : String
                        }
                    )
                )
        }
