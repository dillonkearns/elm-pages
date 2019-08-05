module OpenGraph exposing (Image, article, buildCommon, website)

{-| <https://ogp.me/#>
-}

import Pages.Head as Head


buildCommon : { url : String, siteName : String, image : { url : String, alt : String }, description : String, title : String } -> Common
buildCommon builder =
    { title = builder.title
    , image =
        { url = builder.image.url
        , alt = builder.image.alt
        , dimensions = Nothing
        , mimeType = Nothing
        , secureUrl = Nothing
        }
    , url = builder.url
    , description = builder.description
    , siteName = builder.siteName
    , audio = Nothing
    , video = Nothing
    , locale = Nothing
    , alternateLocales = []
    }


{-| <https://ogp.me/#type_website>
-}
website :
    Common
    -> List Head.Tag
website details =
    Website details |> tags


{-| See <https://ogp.me/#type_article>
-}
article :
    Common
    ->
        { tags : List String
        , section : Maybe String
        , publishedTime : Maybe Iso8601DateTime
        , modifiedTime : Maybe Iso8601DateTime
        , expirationTime : Maybe Iso8601DateTime
        }
    -> List Head.Tag
article common details =
    Article common details |> tags


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
    Book common details |> tags


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


{-| See the audio section in <https://ogp.me/#structured>
Example:

    { url = "http://example.com/sound.mp3"
    , secureUrl = Just "https://secure.example.com/sound.mp3"
     mimeType = Just "audio/mpeg"
    }

-}
type alias Audio =
    { url : String
    , secureUrl : Maybe String
    , mimeType : Maybe String
    }


tagsForAudio : Audio -> List ( String, Maybe String )
tagsForAudio audio =
    [ ( "og:audio", Just audio.url )
    , ( "og:audio:secure_url", audio.secureUrl )
    , ( "og:audio:type", audio.mimeType )
    ]


type alias Locale =
    -- TODO make this more type-safe
    String


type Content
    = Website Common
    | Article
        Common
        { tags : List String
        , section : Maybe String
        , publishedTime : Maybe Iso8601DateTime
        , modifiedTime : Maybe Iso8601DateTime
        , expirationTime : Maybe Iso8601DateTime
        }
    | Book
        Common
        { tags : List String
        , isbn : Maybe String
        , releaseDate : Maybe Iso8601DateTime
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
    , mimeType : Maybe String
    , secureUrl : Maybe String
    }


tagsForImage : Image -> List ( String, Maybe String )
tagsForImage image =
    [ ( "og:image", Just image.url )
    , ( "og:image:secure_url", image.secureUrl )
    , ( "og:image:alt", Just image.alt )
    , ( "og:image:width", image.dimensions |> Maybe.map .width |> Maybe.map String.fromInt )
    , ( "og:image:height", image.dimensions |> Maybe.map .height |> Maybe.map String.fromInt )
    ]


{-| See <https://ogp.me/#structured>
-}
type alias Video =
    { url : String
    , mimeType : Maybe String
    , dimensions : Maybe { width : Int, height : Int }
    , secureUrl : Maybe String
    }


tagsForVideo : Video -> List ( String, Maybe String )
tagsForVideo video =
    [ ( "og:video", Just video.url )
    , ( "og:video:secure_url", video.secureUrl )
    , ( "og:video:width", video.dimensions |> Maybe.map .width |> Maybe.map String.fromInt )
    , ( "og:video:height", video.dimensions |> Maybe.map .height |> Maybe.map String.fromInt )
    ]


tags : Content -> List Head.Tag
tags content =
    (case content of
        Website common ->
            tagsForCommon common
                ++ [ ( "og:type", Just "website" )
                   ]

        Article common details ->
            {-
               TODO
               - article:author - profile array - Writers of the article.
            -}
            tagsForCommon common
                ++ [ ( "og:type", Just "article" )
                   , ( "article:section", details.section )
                   , ( "article:published_time", details.publishedTime )
                   , ( "article:modified_time", details.modifiedTime )
                   , ( "article:expiration_time", details.expirationTime )
                   ]
                ++ List.map
                    (\tag -> ( "article:tag", tag |> Just ))
                    details.tags

        Book common details ->
            tagsForCommon common
                ++ [ ( "og:type", Just "book" )
                   , ( "og:isbn", details.isbn )
                   , ( "og:release_date", details.releaseDate )
                   ]
                ++ List.map
                    (\tag -> ( "book:tag", tag |> Just ))
                    details.tags
    )
        |> List.filterMap
            (\( name, maybeContent ) ->
                maybeContent
                    |> Maybe.map (\metaContent -> Head.metaProperty name metaContent)
            )
