module StructuredData exposing (..)

import Json.Encode as Encode


{-| <https://schema.org/Article>
-}
article : { title : String, description : String, url : String, datePublished : String } -> Encode.Value
article info =
    Encode.object
        [ ( "@context", Encode.string "http://schema.org/" )
        , ( "@type", Encode.string "Article" )
        , ( "name", Encode.string info.title )
        , ( "description", Encode.string info.description )
        , ( "url", Encode.string info.url )
        , ( "datePublished", Encode.string info.datePublished )
        ]


{-|

```json
   {
      "@context": "http://schema.org/",
      "@type": "PodcastSeries",
      "image": "https://www.relay.fm/inquisitive_artwork.png",
      "url": "http://www.relay.fm/inquisitive",
      "name": "Inquisitive",
      "description": "Inquisitive is a show for the naturally curious. Each week, Myke Hurley takes a look at what makes creative people successful and what steps they have taken to get there.",
      "webFeed": "http://www.relay.fm//inquisitive/feed",
      "author": {
        "@type": "Person",
        "name": "Myke Hurley"
      }
    }
   }
```

-}
series : Encode.Value
series =
    Encode.object
        [ ( "@context", Encode.string "http://schema.org/" )
        , ( "@type", Encode.string "PodcastSeries" )
        , ( "image", Encode.string "TODO" )
        , ( "url", Encode.string "http://elm-radio.com/episode/getting-started-with-elm-pages" )
        , ( "name", Encode.string "Elm Radio" )
        , ( "description", Encode.string "TODO" )
        , ( "webFeed", Encode.string "https://elm-radio.com/feed.xml" )
        ]


{-|

```json
   {
      "@context": "http://schema.org/",
      "@type": "PodcastEpisode",
      "url": "http://elm-radio.com/episode/getting-started-with-elm-pages",
     "name": "001: Getting Started with elm-pages",
      "datePublished": "2015-02-18",
      "timeRequired": "PT37M",
      "description": "In the first episode of “Behind the App”, a special series of Inquisitive, we take a look at the beginnings of iOS app development, by focusing on the introduction of the iPhone and the App Store.",
      "associatedMedia": {
        "@type": "MediaObject",
        "contentUrl": "https://cdn.simplecast.com/audio/6a206b/6a206baa-9c8e-4c25-9037-2b674204ba84/ca009f6e-1710-4518-b869-ca34cb0b7d17/001-getting-started-elm-pages_tc.mp3 "
      },
      "partOfSeries": {
        "@type": "PodcastSeries",
        "name": "Elm Radio",
        "url": "https://elm-radio.com"
      }
    }
```

-}
episode : Encode.Value
episode =
    Encode.object
        [ ( "@context", Encode.string "http://schema.org/" )
        , ( "@type", Encode.string "PodcastEpisode" )
        , ( "url", Encode.string "http://elm-radio.com/episode/getting-started-with-elm-pages" )
        , ( "name", Encode.string "Getting Started with elm-pages" )
        , ( "datePublished", Encode.string "2015-02-18" )
        , ( "timeRequired", Encode.string "PT37M" )
        , ( "description", Encode.string "TODO" )
        , ( "associatedMedia"
          , Encode.object
                [ ( "@type", Encode.string "MediaObject" )
                , ( "contentUrl", Encode.string "https://cdn.simplecast.com/audio/6a206b/6a206baa-9c8e-4c25-9037-2b674204ba84/ca009f6e-1710-4518-b869-ca34cb0b7d17/001-getting-started-elm-pages_tc.mp3" )
                ]
          )
        , ( "partOfSeries"
          , Encode.object
                [ ( "@type", Encode.string "PodcastSeries" )
                , ( "name", Encode.string "Elm Radio" )
                , ( "url", Encode.string "https://elm-radio.com" )
                ]
          )
        ]
