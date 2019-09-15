module Head.Twitter exposing (SummarySize(..), TwitterCard(..), rawTags, summaryLarge, summaryRegular)

import Head
import Pages.ImagePath exposing (ImagePath)


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary>
-}
summaryRegular details =
    Summary
        { title = details.title
        , description = details.description
        , siteUser = details.siteUser
        , image = details.image
        , size = Regular
        }
        |> tags


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary-card-with-large-image.html>
-}
summaryLarge details =
    Summary
        { title = details.title
        , description = details.description
        , siteUser = details.siteUser
        , image = details.image
        , size = Large
        }
        |> tags


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/app-card>
-}
app :
    { title : String
    , description : Maybe String
    , siteUser : String
    , image : Maybe (Image pathKey)
    , appIdIphone : Maybe Int
    , appIdIpad : Maybe Int
    , appIdGooglePlay : Maybe String
    , appUrlIphone : Maybe String
    , appUrlIpad : Maybe String
    , appUrlGooglePlay : Maybe String
    , appCountry : Maybe String
    , appNameIphone : Maybe String
    , appNameIpad : Maybe String
    , appNameGooglePlay : Maybe String
    }
    -> List (Head.Tag pathKey)
app details =
    App details
        |> tags


ensureAtPrefix : String -> String
ensureAtPrefix twitterUsername =
    if twitterUsername |> String.startsWith "@" then
        twitterUsername

    else
        "@" ++ twitterUsername


type SummarySize
    = Regular
    | Large


type alias Image pathKey =
    { url : ImagePath pathKey
    , alt : String
    }


type TwitterCard pathKey
    = Summary
        { title : String
        , description : Maybe String
        , siteUser : Maybe String
        , image : Maybe (Image pathKey)
        , size : SummarySize
        }
    | App
        { title : String
        , description : Maybe String
        , siteUser : String
        , image : Maybe (Image pathKey)
        , appIdIphone : Maybe Int
        , appIdIpad : Maybe Int
        , appIdGooglePlay : Maybe String
        , appUrlIphone : Maybe String
        , appUrlIpad : Maybe String
        , appUrlGooglePlay : Maybe String
        , appCountry : Maybe String
        , appNameIphone : Maybe String
        , appNameIpad : Maybe String
        , appNameGooglePlay : Maybe String
        }
      -- https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/player-card
    | Player
        { title : String
        , description : Maybe String
        , siteUser : String
        , image : Image pathKey
        , player : String
        , width : Int
        , height : Int
        }


rawTags : TwitterCard pathKey -> List ( String, Maybe (Head.AttributeValue pathKey) )
rawTags card =
    ( "twitter:card", cardValue card |> Head.raw |> Just )
        :: (case card of
                Summary details ->
                    [ ( "twitter:title", details.title |> Head.raw |> Just )
                    , ( "twitter:site", details.siteUser |> Maybe.map Head.raw )
                    , ( "twitter:description", details.description |> Maybe.map Head.raw )
                    , ( "twitter:image", details.image |> Maybe.map .url |> Maybe.map Head.fullImageUrl )
                    , ( "twitter:image:alt", details.image |> Maybe.map .alt |> Maybe.map Head.raw )
                    ]

                App details ->
                    [ ( "twitter:title", details.title |> Head.raw |> Just )
                    , ( "twitter:site", details.siteUser |> Head.raw |> Just )
                    , ( "twitter:description", details.description |> Maybe.map Head.raw )
                    , ( "twitter:image", details.image |> Maybe.map .url |> Maybe.map Head.fullImageUrl )
                    , ( "twitter:image:alt", details.image |> Maybe.map .alt |> Maybe.map Head.raw )
                    , ( "twitter:app:name:iphone", details.appNameIphone |> Maybe.map Head.raw )
                    , ( "twitter:app:name:ipad", details.appNameIpad |> Maybe.map Head.raw )
                    , ( "twitter:app:name:googleplay", details.appNameGooglePlay |> Maybe.map Head.raw )
                    , ( "twitter:app:id:iphone", details.appIdIphone |> Maybe.map String.fromInt |> Maybe.map Head.raw )
                    , ( "twitter:app:id:ipad", details.appIdIpad |> Maybe.map String.fromInt |> Maybe.map Head.raw )
                    , ( "twitter:app:id:googleplay", details.appIdGooglePlay |> Maybe.map Head.raw )
                    , ( "twitter:app:url:iphone", details.appUrlIphone |> Maybe.map Head.raw )
                    , ( "twitter:app:url:ipad", details.appUrlIpad |> Maybe.map Head.raw )
                    , ( "twitter:app:url:googleplay", details.appUrlGooglePlay |> Maybe.map Head.raw )
                    , ( "twitter:app:country", details.appCountry |> Maybe.map Head.raw )
                    ]

                Player details ->
                    [ ( "twitter:title", details.title |> Head.raw |> Just )
                    , ( "twitter:site", details.siteUser |> Head.raw |> Just )
                    , ( "twitter:description", details.description |> Maybe.map Head.raw )
                    , ( "twitter:image", Just (Head.fullImageUrl details.image.url) )
                    , ( "twitter:image:alt", details.image.alt |> Head.raw |> Just )
                    ]
           )


tags : TwitterCard pathKey -> List (Head.Tag pathKey)
tags card =
    card
        |> rawTags
        |> List.filterMap
            (\( name, maybeContent ) ->
                maybeContent
                    |> Maybe.map (\content -> Head.metaName name content)
            )


cardValue : TwitterCard pathKey -> String
cardValue card =
    case card of
        Summary details ->
            case details.size of
                Regular ->
                    "summary"

                Large ->
                    "summary_large_image"

        App details ->
            "app"

        Player details ->
            "player"
