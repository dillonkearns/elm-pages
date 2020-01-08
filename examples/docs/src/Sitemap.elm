module Sitemap exposing (build)

import Date exposing (Date)
import Dict
import Imf.DateTime
import Time
import Xml
import Xml.Encode exposing (..)


build :
    { siteUrl : String
    }
    -> List String
    -> String
build { siteUrl } urls =
    object
        [ ( "urlset"
          , Dict.fromList
                [ ( "xmlns", string "http://www.sitemaps.org/schemas/sitemap/0.9" )
                ]
          , urls
                |> List.map (urlXml siteUrl)
                |> list
          )
        ]
        |> encode 0


urlXml siteUrl url =
    object
        [ ( "url"
          , Dict.empty
          , list
                [ keyValue "loc" <| string (siteUrl ++ url)
                ]
          )
        ]


keyValue : String -> Xml.Value -> Xml.Value
keyValue key value =
    object [ ( key, Dict.empty, value ) ]
