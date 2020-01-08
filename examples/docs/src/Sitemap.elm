module Sitemap exposing (build)

{-| <https://www.sitemaps.org/protocol.html>
-}

import Date exposing (Date)
import Dict
import Imf.DateTime
import Time
import Xml
import Xml.Encode exposing (..)


type alias Entry =
    { path : String
    , lastMod : Maybe String
    }


build :
    { siteUrl : String
    }
    -> List Entry
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


urlXml siteUrl entry =
    object
        [ ( "url"
          , Dict.empty
          , [ string (siteUrl ++ entry.path)
                |> keyValue "loc"
                |> Just
            , entry.lastMod
                |> Maybe.map string
                |> Maybe.map (keyValue "lastmod")
            ]
                |> List.filterMap identity
                |> list
          )
        ]


keyValue : String -> Xml.Value -> Xml.Value
keyValue key value =
    object [ ( key, Dict.empty, value ) ]
