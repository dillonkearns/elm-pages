module Head.Seo exposing (Common, Image, article, audioPlayer, book, profile, song, summary, summaryLarge, videoPlayer, website)

{-| <https://developers.facebook.com/docs/sharing/opengraph>

This module encapsulates some of the best practices for SEO for your site.

`elm-pages` pre-renders the HTML for your pages (either at build-time or server-render time) so that
web crawlers can efficiently and accurately process it. The functions in this module are for use
with the `head` function in your `Route` modules to help you build up a set of `<meta>` tags that
includes common meta tags used for rich link previews, namely [OpenGraph tags](https://ogp.me/) and [Twitter card tags](https://developer.twitter.com/en/docs/twitter-for-websites/cards/overview/abouts-cards).

    import Date
    import Head
    import Head.Seo as Seo


    -- justinmimbs/date package
    type alias ArticleMetadata =
        { title : String
        , description : String
        , published : Date
        , author : Data.Author.Author
        }

    head : ArticleMetadata -> List Head.Tag
    head articleMetadata =
        Seo.summaryLarge
            { canonicalUrlOverride = Nothing
            , siteName = "elm-pages"
            , image =
                { url = Pages.images.icon
                , alt = articleMetadata.description
                , dimensions = Nothing
                , mimeType = Nothing
                }
            , description = articleMetadata.description
            , locale = Nothing
            , title = articleMetadata.title
            }
            |> Seo.article
                { tags = []
                , section = Nothing
                , publishedTime = Just (Date.toIsoString articleMetadata.published)
                , modifiedTime = Nothing
                , expirationTime = Nothing
                }

@docs Common, Image, article, audioPlayer, book, profile, song, summary, summaryLarge, videoPlayer, website

-}

import DateOrDateTime exposing (DateOrDateTime)
import Head
import Head.Twitter as Twitter
import LanguageTag.Country
import LanguageTag.Language
import MimeType exposing (MimeType)
import Pages.Url


{-| Will be displayed as a large card in twitter
See: <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/summary-card-with-large-image>

The options will also be used to build up the appropriate OpenGraph `<meta>` tags.

Note: You cannot include audio or video tags with summaries.
If you want one of those, use `audioPlayer` or `videoPlayer`

-}
summaryLarge :
    { canonicalUrlOverride : Maybe String
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
    { canonicalUrlOverride : Maybe String
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
    { canonicalUrlOverride : Maybe String
    , siteName : String
    , image : Image
    , description : String
    , title : String
    , audio : Audio
    , locale : Maybe Locale
    }
    -> Common
audioPlayer { title, image, canonicalUrlOverride, description, siteName, audio, locale } =
    { title = title
    , image = image
    , canonicalUrlOverride = canonicalUrlOverride
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
    { canonicalUrlOverride : Maybe String
    , siteName : String
    , image : Image
    , description : String
    , title : String
    , video : Video
    , locale : Maybe Locale
    }
    -> Common
videoPlayer { title, image, canonicalUrlOverride, description, siteName, video, locale } =
    { title = title
    , image = image
    , canonicalUrlOverride = canonicalUrlOverride
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
    { canonicalUrlOverride : Maybe String
    , siteName : String
    , image : Image
    , description : String
    , title : String
    , locale : Maybe Locale
    }
    -> Twitter.SummarySize
    -> Common
buildSummary { title, image, canonicalUrlOverride, description, siteName, locale } summarySize =
    { title = title
    , image = image
    , canonicalUrlOverride = canonicalUrlOverride
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
    , publishedTime : Maybe DateOrDateTime
    , modifiedTime : Maybe DateOrDateTime
    , expirationTime : Maybe DateOrDateTime
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
        , releaseDate : Maybe DateOrDateTime
        }
    -> List Head.Tag
book common details =
    Book details |> Content common |> tags


{-| See <https://ogp.me/#type_profile>
-}
profile :
    { firstName : String
    , lastName : String
    , username : Maybe String
    }
    -> Common
    -> List Head.Tag
profile details common =
    Profile details |> Content common |> tags


{-| See <https://ogp.me/#type_music.song>
-}
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
    , canonicalUrlOverride : Maybe String
    , description : String
    , siteName : String
    , audio : Maybe Audio
    , video : Maybe Video
    , locale : Maybe Locale
    , alternateLocales : List Locale
    , twitterCard : Twitter.TwitterCard
    }


localeToString : Locale -> String
localeToString ( language, territory ) =
    LanguageTag.Language.toCodeString language
        ++ "_"
        ++ LanguageTag.Country.toCodeString territory


tagsForCommon : Common -> List ( String, Maybe Head.AttributeValue )
tagsForCommon common =
    tagsForImage common.image
        ++ (common.audio |> Maybe.map tagsForAudio |> Maybe.withDefault [])
        ++ (common.video |> Maybe.map tagsForVideo |> Maybe.withDefault [])
        ++ [ ( "og:title", Just (Head.raw common.title) )
           , ( "og:url", common.canonicalUrlOverride |> Maybe.map Head.raw |> Maybe.withDefault Head.currentPageFullUrl |> Just )
           , ( "og:description", Just (Head.raw common.description) )
           , ( "og:site_name", Just (Head.raw common.siteName) )
           , ( "og:locale", common.locale |> Maybe.map localeToString |> Maybe.map Head.raw )
           ]
        ++ (common.alternateLocales
                |> List.map
                    (\alternateLocale ->
                        ( "og:locale:alternate", alternateLocale |> localeToString |> Head.raw |> Just )
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


tagsForAudio : Audio -> List ( String, Maybe Head.AttributeValue )
tagsForAudio audio =
    [ ( "og:audio", audio.url |> Head.raw |> Just )
    , ( "og:audio:secure_url", audio.url |> Head.raw |> Just )
    , ( "og:audio:type", audio.mimeType |> Maybe.map (MimeType.toString >> Head.raw) )
    ]


type alias Locale =
    ( LanguageTag.Language.Language, LanguageTag.Country.Country )


type Content
    = Content Common ContentDetails


type ContentDetails
    = Website
    | Article
        { tags : List String
        , section : Maybe String
        , publishedTime : Maybe DateOrDateTime
        , modifiedTime : Maybe DateOrDateTime
        , expirationTime : Maybe DateOrDateTime
        }
    | Book
        { tags : List String
        , isbn : Maybe String
        , releaseDate : Maybe DateOrDateTime
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
    | Profile
        { firstName : String
        , lastName : String
        , username : Maybe String
        }


{-| See <https://ogp.me/#structured>
-}
type alias Image =
    { url : Pages.Url.Url
    , alt : String
    , dimensions : Maybe { width : Int, height : Int }
    , mimeType : Maybe MimeType
    }


tagsForImage : Image -> List ( String, Maybe Head.AttributeValue )
tagsForImage image =
    [ ( "og:image", Just (Head.urlAttribute image.url) )
    , ( "og:image:secure_url", Just (Head.urlAttribute image.url) )
    , ( "og:image:alt", image.alt |> Head.raw |> Just )
    , ( "og:image:width", image.dimensions |> Maybe.map .width |> Maybe.map String.fromInt |> Maybe.map Head.raw )
    , ( "og:image:height", image.dimensions |> Maybe.map .height |> Maybe.map String.fromInt |> Maybe.map Head.raw )
    ]


{-| See <https://ogp.me/#structured>
-}
type alias Video =
    { url : String
    , mimeType : Maybe MimeType
    , dimensions : Maybe { width : Int, height : Int }
    }


tagsForVideo : Video -> List ( String, Maybe Head.AttributeValue )
tagsForVideo video =
    [ ( "og:video", video.url |> Head.raw |> Just )
    , ( "og:video:secure_url", video.url |> Head.raw |> Just )
    , ( "og:video:width", video.dimensions |> Maybe.map .width |> Maybe.map String.fromInt |> Maybe.map Head.raw )
    , ( "og:video:height", video.dimensions |> Maybe.map .height |> Maybe.map String.fromInt |> Maybe.map Head.raw )
    , ( "og:video:type", video.mimeType |> Maybe.map (MimeType.toString >> Head.raw) )
    ]


tags : Content -> List Head.Tag
tags (Content common details) =
    tagsForCommon common
        ++ (case details of
                Website ->
                    [ ( "og:type", "website" |> Head.raw |> Just )
                    ]

                Article articleDetails ->
                    {-
                       TODO
                       - article:author - profile array - Writers of the article.
                    -}
                    [ ( "og:type", "article" |> Head.raw |> Just )
                    , ( "article:section", articleDetails.section |> Maybe.map Head.raw )
                    , ( "article:published_time", articleDetails.publishedTime |> Maybe.map (DateOrDateTime.toIso8601 >> Head.raw) )
                    , ( "article:modified_time", articleDetails.modifiedTime |> Maybe.map (DateOrDateTime.toIso8601 >> Head.raw) )
                    , ( "article:expiration_time", articleDetails.expirationTime |> Maybe.map (DateOrDateTime.toIso8601 >> Head.raw) )
                    ]
                        ++ List.map
                            (\tag -> ( "article:tag", tag |> Head.raw |> Just ))
                            articleDetails.tags

                Book bookDetails ->
                    [ ( "og:type", "book" |> Head.raw |> Just )
                    , ( "og:isbn", bookDetails.isbn |> Maybe.map Head.raw )
                    , ( "og:release_date", bookDetails.releaseDate |> Maybe.map (DateOrDateTime.toIso8601 >> Head.raw) )
                    ]
                        ++ List.map
                            (\tag -> ( "book:tag", tag |> Head.raw |> Just ))
                            bookDetails.tags

                Song songDetails ->
                    [ ( "og:type", "music.song" |> Head.raw |> Just )
                    , ( "music:duration", songDetails.duration |> Maybe.map String.fromInt |> Maybe.map Head.raw )
                    , ( "music:album:disc", songDetails.disc |> Maybe.map String.fromInt |> Maybe.map Head.raw )
                    , ( "music:album:track", songDetails.track |> Maybe.map String.fromInt |> Maybe.map Head.raw )
                    ]

                Profile profileDetails ->
                    [ ( "og:type", "profile" |> Head.raw |> Just )
                    , ( "profile:first_name", profileDetails.firstName |> Head.raw |> Just )
                    , ( "profile:last_name", profileDetails.lastName |> Head.raw |> Just )
                    , ( "profile:username", profileDetails.username |> Maybe.map Head.raw )
                    ]
           )
        |> List.filterMap
            (\( name, maybeContent ) ->
                maybeContent
                    |> Maybe.map (\metaContent -> Head.metaProperty name metaContent)
            )
        |> List.append
            [ Head.canonicalLink common.canonicalUrlOverride
            , Head.metaName "description" (Head.raw common.description)
            ]



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
