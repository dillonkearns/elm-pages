module Head.OpenGraph exposing
    ( Image
    , article
    , audioPlayer
    , song
    , summary
    , summaryLarge
    , videoPlayer
    , website
    )

{-| <https://ogp.me/#>
<https://developers.facebook.com/docs/sharing/opengraph>
-}

import Head
import Head.SocialMeta as Twitter


{-| Will be displayed as a large card in twitter
See: <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary-card-with-large-image>

The options will also be used to build up the appropriate OpenGraph `<meta>` tags.

Note: You cannot include audio or video tags with summaries.
If you want one of those, use `audioPlayer` or `videoPlayer`

-}
summaryLarge :
    { url : String
    , siteName : String
    , image : Image
    , description : String
    , title : String
    , locale : Maybe Locale
    }
    -> Common
summaryLarge config =
    buildSummary config Twitter.Large


{-| Will be displayed as a large card in twitter
See: <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary>

    The options will also be used to build up the appropriate OpenGraph `<meta>` tags.

    Note: You cannot include audio or video tags with summaries.
    If you want one of those, use `audioPlayer` or `videoPlayer`

-}
summary :
    { url : String
    , siteName : String
    , image : Image
    , description : String
    , title : String
    , locale : Maybe Locale
    }
    -> Common
summary config =
    buildSummary config Twitter.Regular


{-| Will be displayed as a Player card in twitter
See: <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/player-card>

OpenGraph audio will also be included.
The options will also be used to build up the appropriate OpenGraph `<meta>` tags.

-}
audioPlayer :
    { url : String
    , siteName : String
    , image : Image
    , description : String
    , title : String
    , audio : Audio
    , locale : Maybe Locale
    }
    -> Common
audioPlayer { title, image, url, description, siteName, audio, locale } =
    { title = title
    , image = image
    , url = url
    , description = description
    , siteName = siteName
    , audio = Just audio
    , video = Nothing
    , locale = locale
    , alternateLocales = [] -- TODO remove hardcoding
    , twitterCard =
        Twitter.Player
            { title = title
            , description = Just description
            , siteUser = ""
            , image = { url = image.url, alt = image.alt }
            , player = audio.url

            -- TODO what should I do here? These are requried by Twitter...
            -- probably require them for both (strictest common requirement)
            , width = 0
            , height = 0
            }
    }


{-| Will be displayed as a Player card in twitter
See: <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/player-card>

OpenGraph video will also be included.
The options will also be used to build up the appropriate OpenGraph `<meta>` tags.

-}
videoPlayer :
    { url : String
    , siteName : String
    , image : Image
    , description : String
    , title : String
    , video : Video
    , locale : Maybe Locale
    }
    -> Common
videoPlayer { title, image, url, description, siteName, video, locale } =
    { title = title
    , image = image
    , url = url
    , description = description
    , siteName = siteName
    , audio = Nothing
    , video = Just video
    , locale = locale
    , alternateLocales = [] -- TODO remove hardcoding
    , twitterCard =
        Twitter.Player
            { title = title
            , description = Just description
            , siteUser = ""
            , image = { url = image.url, alt = image.alt }
            , player = video.url

            -- TODO what should I do here? These are requried by Twitter...
            -- probably require them for both (strictest common requirement)
            , width = 0
            , height = 0
            }
    }


buildSummary :
    { url : String
    , siteName : String
    , image : Image
    , description : String
    , title : String
    , locale : Maybe Locale
    }
    -> Twitter.SummarySize
    -> Common
buildSummary { title, image, url, description, siteName, locale } summarySize =
    { title = title
    , image = image
    , url = url
    , description = description
    , siteName = siteName
    , audio = Nothing
    , video = Nothing
    , locale = locale
    , alternateLocales = [] -- TODO remove hardcoding
    , twitterCard =
        Twitter.Summary
            { title = title
            , description = Just description
            , siteUser = Nothing -- TODO remove hardcoding
            , image = Just { url = image.url, alt = image.alt }
            , size = summarySize
            }
    }



-- TODO add constructor Twitter app-card


{-| <https://ogp.me/#type_website>
-}
website :
    Common
    -> List Head.Tag
website common =
    Website |> Content common |> tags


{-| See <https://ogp.me/#type_article>
-}
article :
    { tags : List String
    , section : Maybe String
    , publishedTime : Maybe Iso8601DateTime
    , modifiedTime : Maybe Iso8601DateTime
    , expirationTime : Maybe Iso8601DateTime
    }
    -> Common
    -> List Head.Tag
article details common =
    Article details |> Content common |> tags


{-| See <https://ogp.me/#type_book>
-}
book :
    Common
    ->
        { tags : List String
        , isbn : Maybe String
        , releaseDate : Maybe Iso8601DateTime
        }
    -> List Head.Tag
book common details =
    Book details |> Content common |> tags


song :
    Common
    ->
        { duration : Maybe Int
        , album : Maybe Int
        , disc : Maybe Int
        , track : Maybe Int
        }
    -> List Head.Tag
song common details =
    Song details |> Content common |> tags


{-| These fields apply to any type in the og object types
See <https://ogp.me/#metadata> and <https://ogp.me/#optional>

Skipping this for now, if there's a use case I can add it in:

  - og:determiner - The word that appears before this object's title in a sentence. An enum of (a, an, the, "", auto). If auto is chosen, the consumer of your data should chose between "a" or "an". Default is "" (blank).

-}
type alias Common =
    { title : String
    , image : Image
    , url : String
    , description : String
    , siteName : String
    , audio : Maybe Audio
    , video : Maybe Video
    , locale : Maybe Locale
    , alternateLocales : List Locale
    , twitterCard : Twitter.TwitterCard
    }


tagsForCommon common =
    tagsForImage common.image
        ++ (common.audio |> Maybe.map tagsForAudio |> Maybe.withDefault [])
        ++ (common.video |> Maybe.map tagsForVideo |> Maybe.withDefault [])
        ++ [ ( "og:title", Just common.title )
           , ( "og:url", Just common.url )
           , ( "og:description", Just common.description )
           , ( "og:site_name", Just common.siteName )
           , ( "og:locale", common.locale )
           ]
        ++ (common.alternateLocales
                |> List.map
                    (\alternateLocale ->
                        ( "og:locale:alternate", Just alternateLocale )
                    )
           )
        ++ Twitter.rawTags common.twitterCard


{-| See the audio section in <https://ogp.me/#structured>
Example:

    { url = "https://example.com/sound.mp3"
     mimeType = Just "audio/mpeg"
    }

-}
type alias Audio =
    { url : String
    , mimeType : Maybe MimeType
    }


tagsForAudio : Audio -> List ( String, Maybe String )
tagsForAudio audio =
    [ ( "og:audio", Just audio.url )
    , ( "og:audio:secure_url", Just audio.url )
    , ( "og:audio:type", audio.mimeType )
    ]


type alias Locale =
    -- TODO make this more type-safe
    String


type Content
    = Content Common ContentDetails


type ContentDetails
    = Website
    | Article
        { tags : List String
        , section : Maybe String
        , publishedTime : Maybe Iso8601DateTime
        , modifiedTime : Maybe Iso8601DateTime
        , expirationTime : Maybe Iso8601DateTime
        }
    | Book
        { tags : List String
        , isbn : Maybe String
        , releaseDate : Maybe Iso8601DateTime
        }
    | Song
        {-

           TODO
           music:album - music.album array - The album this song is from.
           music:musician - profile array - The musician that made this song.
        -}
        { duration : Maybe Int
        , album : Maybe Int
        , disc : Maybe Int
        , track : Maybe Int
        }


{-| <https://en.wikipedia.org/wiki/ISO_8601>
-}
type alias Iso8601DateTime =
    -- TODO should be more type-safe here
    String


{-| <https://en.wikipedia.org/wiki/Media_type>
-}
type alias MimeType =
    -- TODO should be more type-safe here
    String


{-| See <https://ogp.me/#structured>
-}
type alias Image =
    { url : String
    , alt : String
    , dimensions : Maybe { width : Int, height : Int }
    , mimeType : Maybe MimeType
    }


tagsForImage : Image -> List ( String, Maybe String )
tagsForImage image =
    [ ( "og:image", Just image.url )
    , ( "og:image:secure_url", Just image.url )
    , ( "og:image:alt", Just image.alt )
    , ( "og:image:width", image.dimensions |> Maybe.map .width |> Maybe.map String.fromInt )
    , ( "og:image:height", image.dimensions |> Maybe.map .height |> Maybe.map String.fromInt )
    ]


{-| See <https://ogp.me/#structured>
-}
type alias Video =
    { url : String
    , mimeType : Maybe MimeType
    , dimensions : Maybe { width : Int, height : Int }
    }


tagsForVideo : Video -> List ( String, Maybe String )
tagsForVideo video =
    [ ( "og:video", Just video.url )
    , ( "og:video:secure_url", Just video.url )
    , ( "og:video:width", video.dimensions |> Maybe.map .width |> Maybe.map String.fromInt )
    , ( "og:video:height", video.dimensions |> Maybe.map .height |> Maybe.map String.fromInt )
    ]


tags : Content -> List Head.Tag
tags (Content common details) =
    tagsForCommon common
        ++ (case details of
                Website ->
                    [ ( "og:type", Just "website" )
                    ]

                Article articleDetails ->
                    {-
                       TODO
                       - article:author - profile array - Writers of the article.
                    -}
                    [ ( "og:type", Just "article" )
                    , ( "article:section", articleDetails.section )
                    , ( "article:published_time", articleDetails.publishedTime )
                    , ( "article:modified_time", articleDetails.modifiedTime )
                    , ( "article:expiration_time", articleDetails.expirationTime )
                    ]
                        ++ List.map
                            (\tag -> ( "article:tag", tag |> Just ))
                            articleDetails.tags

                Book bookDetails ->
                    [ ( "og:type", Just "book" )
                    , ( "og:isbn", bookDetails.isbn )
                    , ( "og:release_date", bookDetails.releaseDate )
                    ]
                        ++ List.map
                            (\tag -> ( "book:tag", tag |> Just ))
                            bookDetails.tags

                Song songDetails ->
                    [ ( "og:type", Just "music.song" )
                    , ( "music:duration", songDetails.duration |> Maybe.map String.fromInt )
                    , ( "music:album:disc", songDetails.disc |> Maybe.map String.fromInt )
                    , ( "music:album:track", songDetails.track |> Maybe.map String.fromInt )
                    ]
           )
        |> List.filterMap
            (\( name, maybeContent ) ->
                maybeContent
                    |> Maybe.map (\metaContent -> Head.metaProperty name metaContent)
            )



{-
   TODO remaining types:


   - music.album
   - music.playlist
   - music.radio_station
   - video.movie
   - video.episode
   - video.tv_show
   - video.other

-}
