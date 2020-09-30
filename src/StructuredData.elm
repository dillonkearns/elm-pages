module StructuredData exposing (..)

import Json.Encode as Encode


{-| <https://schema.org/SoftwareSourceCode>
-}
softwareSourceCode :
    { codeRepositoryUrl : String
    , description : String
    , author : String
    , programmingLanguage : Encode.Value
    }
    -> Encode.Value
softwareSourceCode info =
    Encode.object
        [ ( "@type", Encode.string "SoftwareSourceCode" )
        , ( "codeRepository", Encode.string info.codeRepositoryUrl )
        , ( "description", Encode.string info.description )
        , ( "author", Encode.string info.author )
        , ( "programmingLanguage", info.programmingLanguage )
        ]


{-| <https://schema.org/ComputerLanguage>
-}
computerLanguage : { url : String, name : String, imageUrl : String, identifier : String } -> Encode.Value
computerLanguage info =
    Encode.object
        [ ( "@type", Encode.string "ComputerLanguage" )
        , ( "url", Encode.string info.url )
        , ( "name", Encode.string info.name )
        , ( "image", Encode.string info.imageUrl )
        , ( "identifier", Encode.string info.identifier )
        ]


elmLang : Encode.Value
elmLang =
    computerLanguage
        { url = "http://elm-lang.org/"
        , name = "Elm"
        , imageUrl = "http://elm-lang.org/"
        , identifier = "http://elm-lang.org/"
        }


{-| <https://schema.org/Article>
-}
article :
    { title : String
    , description : String
    , author : StructuredData { authorMemberOf | personOrOrganization : () } authorPossibleFields
    , publisher : StructuredData { publisherMemberOf | personOrOrganization : () } publisherPossibleFields
    , url : String
    , imageUrl : String
    , datePublished : String
    , mainEntityOfPage : Encode.Value
    }
    -> Encode.Value
article info =
    Encode.object
        [ ( "@context", Encode.string "http://schema.org/" )
        , ( "@type", Encode.string "Article" )
        , ( "headline", Encode.string info.title )
        , ( "description", Encode.string info.description )
        , ( "image", Encode.string info.imageUrl )
        , ( "author", encode info.author )
        , ( "publisher", encode info.publisher )
        , ( "url", Encode.string info.url )
        , ( "datePublished", Encode.string info.datePublished )
        , ( "mainEntityOfPage", info.mainEntityOfPage )
        ]


type StructuredData memberOf possibleFields
    = StructuredData String (List ( String, Encode.Value ))


{-| <https://schema.org/Person>
-}
person :
    { name : String
    }
    ->
        StructuredData { personOrOrganization : () }
            { additionalName : ()
            , address : ()
            , affiliation : ()
            }
person info =
    StructuredData "Person" [ ( "name", Encode.string info.name ) ]


additionalName : String -> StructuredData memberOf { possibleFields | additionalName : () } -> StructuredData memberOf possibleFields
additionalName value (StructuredData typeName fields) =
    StructuredData typeName (( "additionalName", Encode.string value ) :: fields)


{-| <https://schema.org/Article>
-}
article_ :
    { title : String
    , description : String
    , author : String
    , publisher : StructuredData { personOrOrganization : () } possibleFieldsPublisher
    , url : String
    , imageUrl : String
    , datePublished : String
    , mainEntityOfPage : Encode.Value
    }
    -> Encode.Value
article_ info =
    Encode.object
        [ ( "@context", Encode.string "http://schema.org/" )
        , ( "@type", Encode.string "Article" )
        , ( "headline", Encode.string info.title )
        , ( "description", Encode.string info.description )
        , ( "image", Encode.string info.imageUrl )
        , ( "author", Encode.string info.author )
        , ( "publisher", encode info.publisher )
        , ( "url", Encode.string info.url )
        , ( "datePublished", Encode.string info.datePublished )
        , ( "mainEntityOfPage", info.mainEntityOfPage )
        ]


encode : StructuredData memberOf possibleFieldsPublisher -> Encode.Value
encode (StructuredData typeName fields) =
    Encode.object
        (( "@type", Encode.string typeName ) :: fields)



--example : StructuredDataHelper { personOrOrganization : () } { address : (), affiliation : () }


example =
    person { name = "Dillon Kearns" }
        |> additionalName "Cornelius"



--organization :
--    {}
--    -> StructuredDataHelper { personOrOrganization : () }
--organization info =
--    StructuredDataHelper "Organization" []
--needsPersonOrOrg : StructuredDataHelper {}
--needsPersonOrOrg =
--    StructuredDataHelper "" []


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
