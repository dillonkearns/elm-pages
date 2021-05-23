module Head.Twitter exposing (SummarySize(..), TwitterCard(..), rawTags)

import Head
import Pages.Url


type SummarySize
    = Regular
    | Large


type alias Image =
    { url : Pages.Url.Url
    , alt : String
    }


type TwitterCard
    = Summary
        { title : String
        , description : Maybe String
        , siteUser : Maybe String
        , image : Maybe Image
        , size : SummarySize
        }
    | App
        { title : String
        , description : Maybe String
        , siteUser : String
        , image : Maybe Image
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
        , image : Image
        , player : String
        , width : Int
        , height : Int
        }


rawTags : TwitterCard -> List ( String, Maybe Head.AttributeValue )
rawTags card =
    ( "twitter:card", cardValue card |> Head.raw |> Just )
        :: (case card of
                Summary details ->
                    [ ( "twitter:title", details.title |> Head.raw |> Just )
                    , ( "twitter:site", details.siteUser |> Maybe.map Head.raw )
                    , ( "twitter:description", details.description |> Maybe.map Head.raw )
                    , ( "twitter:image", details.image |> Maybe.map .url |> Maybe.map Head.urlAttribute )
                    , ( "twitter:image:alt", details.image |> Maybe.map .alt |> Maybe.map Head.raw )
                    ]

                App details ->
                    [ ( "twitter:title", details.title |> Head.raw |> Just )
                    , ( "twitter:site", details.siteUser |> Head.raw |> Just )
                    , ( "twitter:description", details.description |> Maybe.map Head.raw )
                    , ( "twitter:image", details.image |> Maybe.map .url |> Maybe.map Head.urlAttribute )
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
                    , ( "twitter:image", Just (Head.urlAttribute details.image.url) )
                    , ( "twitter:image:alt", details.image.alt |> Head.raw |> Just )
                    ]
           )


cardValue : TwitterCard -> String
cardValue card =
    case card of
        Summary details ->
            case details.size of
                Regular ->
                    "summary"

                Large ->
                    "summary_large_image"

        App _ ->
            "app"

        Player _ ->
            "player"
