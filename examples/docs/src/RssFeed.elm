module RssFeed exposing (Item, generate)

{-| Build a feed following the RSS 2.0 format <https://validator.w3.org/feed/docs/rss2.html>.
<http://www.rssboard.org/rss-specification>
-}

import Date exposing (Date)
import Dict
import Imf.DateTime
import Time
import Xml
import Xml.Encode exposing (..)


type alias Item =
    { title : String
    , description : String
    , url : String
    , categories : List String
    , author : String
    , pubDate : Date
    , content : Maybe String

    {-
       lat optional number The latitude coordinate of the item.
       long optional number The longitude coordinate of the item.
       custom_elements optional array Put additional elements in the item (node-xml syntax)
       enclosure optional object An enclosure object
    -}
    }


generate :
    { title : String
    , description : String
    , url : String
    , lastBuildTime : Time.Posix
    , generator : Maybe String
    , items : List Item
    , siteUrl : String
    }
    -> Xml.Value
generate feed =
    object
        [ ( "rss"
          , Dict.fromList
                [ ( "xmlns:dc", string "http://purl.org/dc/elements/1.1/" )
                , ( "xmlns:content", string "http://purl.org/rss/1.0/modules/content/" )
                , ( "xmlns:atom", string "http://www.w3.org/2005/Atom" )
                , ( "version", string "2.0" )
                ]
          , object
                [ ( "channel"
                  , Dict.empty
                  , [ [ keyValue "title" feed.title
                      , keyValue "description" feed.description
                      , keyValue "link" feed.url

                      --<atom:link href="http://dallas.example.com/rss.xml" rel="self" type="application/rss+xml" />
                      , keyValue "lastBuildDate" <| Imf.DateTime.fromPosix Time.utc feed.lastBuildTime
                      ]
                    , [ feed.generator |> Maybe.map (keyValue "generator") ] |> List.filterMap identity
                    , List.map (itemXml feed.siteUrl) feed.items
                    ]
                        |> List.concat
                        |> list
                  )
                ]
          )
        ]


itemXml : String -> Item -> Xml.Value
itemXml siteUrl item =
    object
        [ ( "item"
          , Dict.empty
          , list
                ([ keyValue "title" item.title
                 , keyValue "description" item.description
                 , keyValue "link" (siteUrl ++ item.url)
                 , keyValue "guid" (siteUrl ++ item.url)
                 , keyValue "pubDate" (formatDate item.pubDate)
                 ]
                    ++ ([ item.content |> Maybe.map (\content -> keyValue "content" content)
                        ]
                            |> List.filterMap identity
                       )
                )
          )
        ]


formatDate : Date -> String
formatDate date =
    Date.format "EEE, dd MMM yyyy" date
        ++ " 00:00:00 GMT"


generatorXml : String -> Xml.Value
generatorXml generator =
    Xml.Encode.object [ ( "generator", Dict.empty, Xml.Encode.string generator ) ]


keyValue : String -> String -> Xml.Value
keyValue key value =
    object [ ( key, Dict.empty, string value ) ]
