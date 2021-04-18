module Pages.SiteConfig exposing (SiteConfig)

import Head
import Pages.Manifest
import Pages.StaticHttp as StaticHttp


type alias SiteConfig route staticData =
    List route
    ->
        { staticData : StaticHttp.Request staticData
        , canonicalUrl : String
        , manifest : staticData -> Pages.Manifest.Config
        , head :
            staticData
            -> List Head.Tag
        , generateFiles :
            StaticHttp.Request
                (List
                    (Result
                        String
                        { path : List String
                        , content : String
                        }
                    )
                )
        }
