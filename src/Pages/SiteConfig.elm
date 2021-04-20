module Pages.SiteConfig exposing (SiteConfig)

import DataSource
import Head
import Pages.Manifest


type alias SiteConfig route staticData =
    List route
    ->
        { staticData : DataSource.Request staticData
        , canonicalUrl : String
        , manifest : staticData -> Pages.Manifest.Config
        , head :
            staticData
            -> List Head.Tag
        , generateFiles :
            DataSource.Request
                (List
                    (Result
                        String
                        { path : List String
                        , content : String
                        }
                    )
                )
        }
