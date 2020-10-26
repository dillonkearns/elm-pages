module Head exposing
    ( Tag, metaName, metaProperty
    , rssLink, sitemapLink
    , structuredData
    , AttributeValue
    , currentPageFullUrl, fullImageUrl, fullPageUrl, raw
    , appleTouchIcon, icon
    , toJson, canonicalLink
    )

{-| This module contains low-level functions for building up
values that will be rendered into the page's `<head>` tag
when you run `elm-pages build`. Most likely the `Head.Seo` module
will do everything you need out of the box, and you will just need to import `Head`
so you can use the `Tag` type in your type annotations.

But this module might be useful if you have a special use case, or if you are
writing a plugin package to extend `elm-pages`.

@docs Tag, metaName, metaProperty
@docs rssLink, sitemapLink


## Structured Data

@docs structuredData


## `AttributeValue`s

@docs AttributeValue
@docs currentPageFullUrl, fullImageUrl, fullPageUrl, raw


## Icons

@docs appleTouchIcon, icon


## Functions for use by generated code

@docs toJson, canonicalLink

-}

import Codec exposing (Codec)
import Json.Encode
import MimeType
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Internal.String as String
import Pages.PagePath as PagePath exposing (PagePath)


{-| Values that can be passed to the generated `Pages.application` config
through the `head` function.
-}
type Tag pathKey
    = Tag (Details pathKey)
    | StructuredData Json.Encode.Value


type alias Details pathKey =
    { name : String
    , attributes : List ( String, AttributeValue pathKey )
    }


{-| You can learn more about structured data in [Google's intro to structured data](https://developers.google.com/search/docs/guides/intro-structured-data).

When you add a `structuredData` item to one of your pages in `elm-pages`, it will add `json-ld` data to your document that looks like this:

```html
<script type="application/ld+json">
{
   "@context":"http://schema.org/",
   "@type":"Article",
   "headline":"Extensible Markdown Parsing in Pure Elm",
   "description":"Introducing a new parser that extends your palette with no additional syntax",
   "image":"https://elm-pages.com/images/article-covers/extensible-markdown-parsing.jpg",
   "author":{
      "@type":"Person",
      "name":"Dillon Kearns"
   },
   "publisher":{
      "@type":"Person",
      "name":"Dillon Kearns"
   },
   "url":"https://elm-pages.com/blog/extensible-markdown-parsing-in-elm",
   "datePublished":"2019-10-08",
   "mainEntityOfPage":{
      "@type":"SoftwareSourceCode",
      "codeRepository":"https://github.com/dillonkearns/elm-pages",
      "description":"A statically typed site generator for Elm.",
      "author":"Dillon Kearns",
      "programmingLanguage":{
         "@type":"ComputerLanguage",
         "url":"http://elm-lang.org/",
         "name":"Elm",
         "image":"http://elm-lang.org/",
         "identifier":"http://elm-lang.org/"
      }
   }
}
</script>
```

To get that data, you would write this in your `elm-pages` head tags:

    import Json.Encode as Encode

    {-| <https://schema.org/Article>
    -}
    encodeArticle :
        { title : String
        , description : String
        , author : StructuredDataHelper { authorMemberOf | personOrOrganization : () } authorPossibleFields
        , publisher : StructuredDataHelper { publisherMemberOf | personOrOrganization : () } publisherPossibleFields
        , url : String
        , imageUrl : String
        , datePublished : String
        , mainEntityOfPage : Encode.Value
        }
        -> Head.Tag pathKey
    encodeArticle info =
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
            |> Head.structuredData

Take a look at this [Google Search Gallery](https://developers.google.com/search/docs/guides/search-gallery)
to see some examples of how structured data can be used by search engines to give rich search results. It can help boost
your rankings, get better engagement for your content, and also make your content more accessible. For example,
voice assistant devices can make use of structured data. If you're hosting a conference and want to make the event
date and location easy for attendees to find, this can make that information more accessible.

For the current version of API, you'll need to make sure that the format is correct and contains the required and recommended
structure.

Check out <https://schema.org> for a comprehensive listing of possible data types and fields. And take a look at
Google's [Structured Data Testing Tool](https://search.google.com/structured-data/testing-tool)
too make sure that your structured data is valid and includes the recommended values.

In the future, `elm-pages` will likely support a typed API, but schema.org is a massive spec, and changes frequently.
And there are multiple sources of information on the possible and recommended structure. So it will take some time
for the right API design to evolve. In the meantime, this allows you to make use of this for SEO purposes.

-}
structuredData : Json.Encode.Value -> Tag pathKey
structuredData value =
    StructuredData value


{-| Create a raw `AttributeValue` (as opposed to some kind of absolute URL).
-}
raw : String -> AttributeValue pathKey
raw value =
    Raw value


{-| Create an `AttributeValue` from an `ImagePath`.
-}
fullImageUrl : ImagePath pathKey -> AttributeValue pathKey
fullImageUrl value =
    FullImageUrl value


{-| Create an `AttributeValue` from a `PagePath`.
-}
fullPageUrl : PagePath pathKey -> AttributeValue pathKey
fullPageUrl value =
    FullUrl (PagePath.toString value)


{-| Create an `AttributeValue` representing the current page's full url.
-}
currentPageFullUrl : AttributeValue pathKey
currentPageFullUrl =
    FullUrlToCurrentPage


{-| Values, such as between the `<>`'s here:

```html
<meta name="<THIS IS A VALUE>" content="<THIS IS A VALUE>" />
```

-}
type AttributeValue pathKey
    = Raw String
    | FullUrl String
    | FullImageUrl (ImagePath pathKey)
    | FullUrlToCurrentPage


{-| It's recommended that you use the `Seo` module helpers, which will provide this
for you, rather than directly using this.

Example:

    Head.canonicalLink "https://elm-pages.com"

-}
canonicalLink : Maybe (PagePath pathKey) -> Tag pathKey
canonicalLink maybePath =
    node "link"
        [ ( "rel", raw "canonical" )
        , ( "href"
          , maybePath |> Maybe.map fullPageUrl |> Maybe.withDefault currentPageFullUrl
          )
        ]


{-| Add a link to the site's RSS feed.

Example:

    rssLink "/feed.xml"

```html
<link rel="alternate" type="application/rss+xml" href="/rss.xml">
```

-}
rssLink : String -> Tag pathKey
rssLink url =
    node "link"
        [ ( "rel", raw "alternate" )
        , ( "type", raw "application/rss+xml" )
        , ( "href", raw url )
        ]


{-| -}
icon : List ( Int, Int ) -> MimeType.MimeImage -> ImagePath pathKey -> Tag pathKey
icon sizes imageMimeType image =
    -- TODO allow "any" for sizes value
    [ ( "rel", raw "icon" |> Just )
    , ( "sizes"
      , sizes
            |> nonEmptyList
            |> Maybe.map sizesToString
            |> Maybe.map raw
      )
    , ( "type", imageMimeType |> MimeType.Image |> MimeType.toString |> raw |> Just )
    , ( "href", fullImageUrl image |> Just )
    ]
        |> filterMaybeValues
        |> node "link"


nonEmptyList : List a -> Maybe (List a)
nonEmptyList list =
    if List.isEmpty list then
        Nothing

    else
        Just list


{-| Note: the type must be png.
See <https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/ConfiguringWebApplications/ConfiguringWebApplications.html>.

If a size is provided, it will be turned into square dimensions as per the recommendations here: <https://developers.google.com/web/fundamentals/design-and-ux/browser-customization/#safari>

Images must be png's, and non-transparent images are recommended. Current recommended dimensions are 180px and 192px.

-}
appleTouchIcon : Maybe Int -> ImagePath pathKey -> Tag pathKey
appleTouchIcon maybeSize image =
    [ ( "rel", raw "apple-touch-icon" |> Just )
    , ( "sizes"
      , maybeSize
            |> Maybe.map (\size -> sizesToString [ ( size, size ) ])
            |> Maybe.map raw
      )
    , ( "href", fullImageUrl image |> Just )
    ]
        |> filterMaybeValues
        |> node "link"


filterMaybeValues : List ( String, Maybe a ) -> List ( String, a )
filterMaybeValues list =
    list
        |> List.filterMap
            (\( key, maybeValue ) ->
                case maybeValue of
                    Just value ->
                        Just ( key, value )

                    Nothing ->
                        Nothing
            )


sizesToString : List ( Int, Int ) -> String
sizesToString sizes =
    sizes
        |> List.map (\( x, y ) -> String.fromInt x ++ "x" ++ String.fromInt y)
        |> String.join " "


{-| Add a link to the site's RSS feed.

Example:

    sitemapLink "/feed.xml"

```html
<link rel="sitemap" type="application/xml" href="/sitemap.xml">
```

-}
sitemapLink : String -> Tag pathKey
sitemapLink url =
    node "link"
        [ ( "rel", raw "sitemap" )
        , ( "type", raw "application/xml" )
        , ( "href", raw url )
        ]


{-| Example:

    Head.metaProperty "fb:app_id" (Head.raw "123456789")

Results in `<meta property="fb:app_id" content="123456789" />`

-}
metaProperty : String -> AttributeValue pathKey -> Tag pathKey
metaProperty property content =
    node "meta"
        [ ( "property", raw property )
        , ( "content", content )
        ]


{-| Example:

    metaName
        [ ( "name", "twitter:card" )
        , ( "content", "summary_large_image" )
        ]

Results in `<meta name="twitter:card" content="summary_large_image" />`

-}
metaName : String -> AttributeValue pathKey -> Tag pathKey
metaName name content =
    node "meta"
        [ ( "name", Raw name )
        , ( "content", content )
        ]


{-| Low-level function for creating a tag for the HTML document's `<head>`.
-}
node : String -> List ( String, AttributeValue pathKey ) -> Tag pathKey
node name attributes =
    Tag
        { name = name
        , attributes = attributes
        }


{-| Feel free to use this, but in 99% of cases you won't need it. The generated
code will run this for you to generate your `manifest.json` file automatically!
-}
toJson : String -> String -> Tag pathKey -> Json.Encode.Value
toJson canonicalSiteUrl currentPagePath tag =
    case tag of
        Tag headTag ->
            Json.Encode.object
                [ ( "name", Json.Encode.string headTag.name )
                , ( "attributes", Json.Encode.list (encodeProperty canonicalSiteUrl currentPagePath) headTag.attributes )
                , ( "type", Json.Encode.string "head" )
                ]

        StructuredData value ->
            Json.Encode.object
                [ ( "contents", value )
                , ( "type", Json.Encode.string "json-ld" )
                ]


encodeProperty : String -> String -> ( String, AttributeValue pathKey ) -> Json.Encode.Value
encodeProperty canonicalSiteUrl currentPagePath ( name, value ) =
    case value of
        Raw rawValue ->
            Json.Encode.list Json.Encode.string [ name, rawValue ]

        FullUrl urlPath ->
            Json.Encode.list Json.Encode.string [ name, joinPaths canonicalSiteUrl urlPath ]

        FullUrlToCurrentPage ->
            Json.Encode.list Json.Encode.string [ name, joinPaths canonicalSiteUrl currentPagePath ]

        FullImageUrl imagePath ->
            Json.Encode.list Json.Encode.string [ name, ImagePath.toAbsoluteUrl canonicalSiteUrl imagePath ]


joinPaths : String -> String -> String
joinPaths base path =
    String.chopEnd "/" base ++ "/" ++ String.chopStart "/" path
