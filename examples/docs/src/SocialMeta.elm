module SocialMeta exposing (TwitterCard(..))

import Pages.Head as Head


type SummarySize
    = Regular
    | Large


type TwitterCard
    = -- https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary
      -- https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary-card-with-large-image.html
      Summary
        { title : String
        , description : Maybe String
        , siteUser : Maybe String
        , image : Maybe { url : String, alt : String }
        , size : SummarySize
        }
      -- https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/app-card
    | App
        { title : String
        , description : Maybe String
        , siteUser : String
        , image : Maybe { url : String, alt : String }
        , appIdIphone : Int
        , appIdIpad : Int
        , appIdGooglePlay : String
        , appUrlIphone : Maybe String
        , appUrlIpad : Maybe String
        , appUrlGooglePlay : Maybe String
        , appCountry : Maybe String
        }
      -- https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/player-card
    | Player
        { title : String
        , description : Maybe String
        , siteUser : String
        , image : { url : String, alt : String }
        , player : String
        , width : Int
        , height : Int
        }


tags : TwitterCard -> List Head.Tag
tags card =
    [ ( "twitter:card", cardValue card |> Just )
    ]
        |> List.filterMap
            (\( name, maybeContent ) ->
                maybeContent
                    |> Maybe.map (\content -> Head.metaName name content)
            )



--   ("twitter:title", title)
--   -- optional
--    ("twitter:site", siteUser)
--   ("twitter:description", description)
--    ("twitter:image", image)
--    ("twitter:image:alt", imageAlt)


cardValue : TwitterCard -> String
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
