module SocialMeta exposing (TwitterCard(..))

import Pages.Head as Head


type TwitterCard
    = -- https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary
      -- optional "twitter:site"
      Summary
        { title : String
        , description : Maybe String
        , siteUser : Maybe String
        , image : Maybe { url : String, alt : String }
        }
    | SummaryLargeImage


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
--   ("twitter:description", description)
--    ("twitter:site", siteUser)
--    ("twitter:image", image)
--    ("twitter:image:alt", imageAlt)


cardValue : TwitterCard -> String
cardValue card =
    case card of
        Summary details ->
            "summary"

        SummaryLargeImage ->
            "summary_large_image"
