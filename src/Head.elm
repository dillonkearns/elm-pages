module Head exposing
    ( Tag, metaName, metaProperty, metaRedirect
    , rssLink, sitemapLink, rootLanguage, manifestLink
    , nonLoadingNode
    , structuredData
    , AttributeValue
    , currentPageFullUrl, urlAttribute, raw
    , appleTouchIcon, icon
    , toJson, canonicalLink
    )

{-| This module contains functions for building up
tags with metadata that will be rendered into the page's `<head>` tag
when your page is pre-rendered (or server-rendered, in the case of your server-rendered Route Modules). See also [`Head.Seo`](Head-Seo),
which has some helper functions for defining OpenGraph and Twitter tags.

One of the unique benefits of using `elm-pages` is that all of your routes (both pre-rendered and server-rendered) fully
render the HTML of your page. That includes the full initial `view` (with the BackendTask resolved, and the `Model` from `init`).
The HTML response also includes all of the `Head` tags, which are defined in two places:

1.  `app/Site.elm` - there is a `head` definition in `Site.elm` where you define global head tags that will be included on every rendered page.

2.  In each Route Module - there is a `head` function where you have access to both the resolved `BackendTask` and the `RouteParams` for the page and can return head tags based on that.

Here is a common set of global head tags that we can define in `Site.elm`:

    module Site exposing (canonicalUrl, config)

    import BackendTask exposing (BackendTask)
    import Head
    import MimeType
    import SiteConfig exposing (SiteConfig)

    config : SiteConfig
    config =
    { canonicalUrl = "<https://elm-pages.com">
    , head = head
    }

    head : BackendTask (List Head.Tag)
    head =
    [ Head.metaName "viewport" (Head.raw "width=device-width,initial-scale=1")
    , Head.metaName "mobile-web-app-capable" (Head.raw "yes")
    , Head.metaName "theme-color" (Head.raw "#ffffff")
    , Head.metaName "apple-mobile-web-app-capable" (Head.raw "yes")
    , Head.metaName "apple-mobile-web-app-status-bar-style" (Head.raw "black-translucent")
    , Head.icon [ ( 32, 32 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 32)
    , Head.icon [ ( 16, 16 ) ] MimeType.Png (cloudinaryIcon MimeType.Png 16)
    , Head.appleTouchIcon (Just 180) (cloudinaryIcon MimeType.Png 180)
    , Head.appleTouchIcon (Just 192) (cloudinaryIcon MimeType.Png 192)
    ]
    |> BackendTask.succeed

And here is a `head` function for a Route Module for a blog post. Note that we have access to our `BackendTask` Data and
are using it to populate article metadata like the article's image, publish date, etc.

    import Article
    import BackendTask
    import Date
    import Head
    import Head.Seo
    import Path
    import Route exposing (Route)
    import RouteBuilder exposing (App, StatelessRoute)

    type alias RouteParams =
        { slug : String }

    type alias Data =
        { metadata : ArticleMetadata
        , body : List Markdown.Block.Block
        }

    route : StatelessRoute RouteParams Data ActionData
    route =
        RouteBuilder.preRender
            { data = data
            , head = head
            , pages = pages
            }
            |> RouteBuilder.buildNoState { view = view }

    head :
        App Data ActionData RouteParams
        -> List Head.Tag
    head static =
        let
            metadata =
                static.data.metadata
        in
        Head.Seo.summaryLarge
            { canonicalUrlOverride = Nothing
            , siteName = "elm-pages"
            , image =
                { url = metadata.image
                , alt = metadata.description
                , dimensions = Nothing
                , mimeType = Nothing
                }
            , description = metadata.description
            , locale = Nothing
            , title = metadata.title
            }
            |> Head.Seo.article
                { tags = []
                , section = Nothing
                , publishedTime = Just (DateOrDateTime.Date metadata.published)
                , modifiedTime = Nothing
                , expirationTime = Nothing
                }


## Why is pre-rendered HTML important? Does it still matter for SEO?

Many search engines are able to execute JavaScript now. However, not all are, and even with crawlers like Google, there
is a longer lead time for your pages to be indexed when you have HTML with a blank page that is only visible after the JavaScript executes.

But most importantly, many tools that unfurl links will not execute JavaScript at all, but rather simply do a simple pass to parse your `<head>` tags.
It is not viable or reliable to add `<head>` tags for metadata on the client-side, it must be present in the initial HTML payload. Otherwise you may not
get unfurling preview content when you share a link to your site on Slack, Twitter, etc.


## Building up Head Tags

@docs Tag, metaName, metaProperty, metaRedirect
@docs rssLink, sitemapLink, rootLanguage, manifestLink

@docs nonLoadingNode


## Structured Data

@docs structuredData


## `AttributeValue`s

@docs AttributeValue
@docs currentPageFullUrl, urlAttribute, raw


## Icons

@docs appleTouchIcon, icon


## Functions for use by generated code

@docs toJson, canonicalLink

-}

import Json.Encode
import LanguageTag exposing (LanguageTag)
import List.Extra
import MimeType
import Pages.Internal.String as String
import Pages.Url
import Regex


{-| Values that can be passed to the generated `Pages.application` config
through the `head` function.
-}
type Tag
    = Tag Details
    | StructuredData Json.Encode.Value
    | RootModifier String String
    | Stripped String


type alias Details =
    { name : String
    , attributes : List ( String, AttributeValue )
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
        -> Head.Tag
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
structuredData : Json.Encode.Value -> Tag
structuredData value =
    StructuredData value


{-| Create a raw `AttributeValue` (as opposed to some kind of absolute URL).
-}
raw : String -> AttributeValue
raw value =
    Raw value


{-| Create an `AttributeValue` from an `ImagePath`.
-}
urlAttribute : Pages.Url.Url -> AttributeValue
urlAttribute value =
    FullUrl value


{-| Create an `AttributeValue` representing the current page's full url.
-}
currentPageFullUrl : AttributeValue
currentPageFullUrl =
    FullUrlToCurrentPage


{-| Values, such as between the `<>`'s here:

```html
<meta name="<THIS IS A VALUE>" content="<THIS IS A VALUE>" />
```

-}
type AttributeValue
    = Raw String
    | FullUrl Pages.Url.Url
    | FullUrlToCurrentPage


{-| It's recommended that you use the `Seo` module helpers, which will provide this
for you, rather than directly using this.

Example:

    Head.canonicalLink "https://elm-pages.com"

-}
canonicalLink : Maybe String -> Tag
canonicalLink maybePath =
    node "link"
        [ ( "rel", raw "canonical" )
        , ( "href"
          , maybePath |> Maybe.map raw |> Maybe.withDefault currentPageFullUrl
          )
        ]


{-| Escape hatch for any head tags that don't have high-level helpers. This lets you build arbitrary head nodes as long as they
are not loading or preloading directives.

Tags that do loading/pre-loading will not work from this function. `elm-pages` uses ViteJS for loading assets like
script tags, stylesheets, fonts, etc., and allows you to customize which assets to preload and how through the elm-pages.config.mjs file.
See the full discussion of the design in [#339](https://github.com/dillonkearns/elm-pages/discussions/339).

So for example the following tags would _not_ load if defined through `nonLoadingNode`, and would instead need to be registered through Vite:

  - `<script src="...">`
  - `<link href="/style.css">`
  - `<link rel="preload">`

The following tag would successfully render as it is a non-loading tag:

    Head.nonLoadingNode "link"
        [ ( "rel", Head.raw "alternate" )
        , ( "type", Head.raw "application/atom+xml" )
        , ( "title", Head.raw "News" )
        , ( "href", Head.raw "/news/atom" )
        ]

Renders the head tag:

`<link rel="alternate" type="application/atom+xml" title="News" href="/news/atom">`

-}
nonLoadingNode : String -> List ( String, AttributeValue ) -> Tag
nonLoadingNode nodeName attributes =
    let
        relTag : Maybe AttributeValue
        relTag =
            attributes
                |> List.Extra.find (\( key, _ ) -> key == "rel")
                |> Maybe.map Tuple.second

        isPreloadDirective : Bool
        isPreloadDirective =
            case relTag of
                Just (Raw rel) ->
                    let
                        isLinkTag : Bool
                        isLinkTag =
                            nodeName |> matchesKeyword "link"
                    in
                    isLinkTag
                        && (rel
                                |> matchesOneKeyword
                                    [ "preload"
                                    , "modulepreload"
                                    , "preconnect"
                                    , "dns-prefetch"
                                    , "stylesheet"
                                    ]
                           )

                _ ->
                    False
    in
    if
        (nodeName |> matchesKeyword "script")
            || isPreloadDirective
    then
        Stripped
            ("<"
                ++ nodeName
                ++ " "
                ++ (attributes
                        |> List.map
                            (\( name, value ) ->
                                name
                                    ++ "=\""
                                    ++ ((case value of
                                            Raw rawValue ->
                                                rawValue

                                            _ ->
                                                "<internals>"
                                        )
                                            ++ "\""
                                       )
                            )
                        |> String.join " "
                   )
                ++ " />"
            )

    else
        node nodeName attributes


matchesOneKeyword : List String -> String -> Bool
matchesOneKeyword keywords string =
    List.any
        (\keyword -> string |> matchesKeyword keyword)
        keywords


matchesKeyword : String -> String -> Bool
matchesKeyword regex string =
    string |> matchesRegex ("^\\s*" ++ regex ++ "\\s*$")


matchesRegex : String -> String -> Bool
matchesRegex regex string =
    string
        |> Regex.contains
            (Regex.fromStringWith
                { caseInsensitive = True, multiline = True }
                regex
                |> Maybe.withDefault Regex.never
            )


{-| Let's you link to your manifest.json file, see <https://developer.mozilla.org/en-US/docs/Web/Manifest#deploying_a_manifest>.
-}
manifestLink : String -> Tag
manifestLink path =
    node "link"
        [ ( "rel", raw "manifest" )
        , ( "href", raw path )
        ]


{-| Add a link to the site's RSS feed.

Example:

    rssLink "/feed.xml"

```html
<link rel="alternate" type="application/rss+xml" href="/rss.xml">
```

-}
rssLink : String -> Tag
rssLink url =
    node "link"
        [ ( "rel", raw "alternate" )
        , ( "type", raw "application/rss+xml" )
        , ( "href", raw url )
        ]


{-| -}
icon : List ( Int, Int ) -> MimeType.MimeImage -> Pages.Url.Url -> Tag
icon sizes imageMimeType imageUrl =
    -- TODO allow "any" for sizes value
    [ ( "rel", raw "icon" |> Just )
    , ( "sizes"
      , sizes
            |> nonEmptyList
            |> Maybe.map sizesToString
            |> Maybe.map raw
      )
    , ( "type", imageMimeType |> MimeType.Image |> MimeType.toString |> raw |> Just )
    , ( "href", urlAttribute imageUrl |> Just )
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
appleTouchIcon : Maybe Int -> Pages.Url.Url -> Tag
appleTouchIcon maybeSize imageUrl =
    [ ( "rel", raw "apple-touch-icon" |> Just )
    , ( "sizes"
      , maybeSize
            |> Maybe.map (\size -> sizesToString [ ( size, size ) ])
            |> Maybe.map raw
      )
    , ( "href", urlAttribute imageUrl |> Just )
    ]
        |> filterMaybeValues
        |> node "link"


{-| Set the language for a page.

<https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/lang>

    import Head
    import LanguageTag
    import LanguageTag.Language

    LanguageTag.Language.de -- sets the page's language to German
        |> LanguageTag.build LanguageTag.emptySubtags
        |> Head.rootLanguage

This results pre-rendered HTML with a global lang tag set.

```html
<html lang="no">
...
</html>
```

-}
rootLanguage : LanguageTag -> Tag
rootLanguage languageTag =
    languageTag
        |> LanguageTag.toString
        |> RootModifier "lang"



-- TODO rootDirection for


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
sitemapLink : String -> Tag
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
metaProperty : String -> AttributeValue -> Tag
metaProperty property content =
    node "meta"
        [ ( "property", raw property )
        , ( "content", content )
        ]


{-| Example:

    Head.metaName "twitter:card" (Head.raw "summary_large_image")

Results in `<meta name="twitter:card" content="summary_large_image" />`

-}
metaName : String -> AttributeValue -> Tag
metaName name content =
    node "meta"
        [ ( "name", Raw name )
        , ( "content", content )
        ]


{-| Example:

    metaRedirect (Raw "0; url=https://google.com")

Results in `<meta http-equiv="refresh" content="0; url=https://google.com" />`

-}
metaRedirect : AttributeValue -> Tag
metaRedirect content =
    node "meta"
        [ ( "http-equiv", Raw "refresh" )
        , ( "content", content )
        ]


{-| Low-level function for creating a tag for the HTML document's `<head>`.
-}
node : String -> List ( String, AttributeValue ) -> Tag
node name attributes =
    Tag
        { name = name
        , attributes = attributes
        }


{-| Feel free to use this, but in 99% of cases you won't need it. The generated
code will run this for you to generate your `manifest.json` file automatically!
-}
toJson : String -> String -> Tag -> Json.Encode.Value
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

        RootModifier key value ->
            Json.Encode.object
                [ ( "type", Json.Encode.string "root" )
                , ( "keyValuePair", Json.Encode.list Json.Encode.string [ key, value ] )
                ]

        Stripped message ->
            Json.Encode.object
                [ ( "type", Json.Encode.string "stripped" )
                , ( "message", Json.Encode.string message )
                ]


encodeProperty : String -> String -> ( String, AttributeValue ) -> Json.Encode.Value
encodeProperty canonicalSiteUrl currentPagePath ( name, value ) =
    case value of
        Raw rawValue ->
            Json.Encode.list Json.Encode.string [ name, rawValue ]

        FullUrlToCurrentPage ->
            Json.Encode.list Json.Encode.string [ name, joinPaths canonicalSiteUrl currentPagePath ]

        FullUrl url ->
            Json.Encode.list Json.Encode.string [ name, Pages.Url.toAbsoluteUrl canonicalSiteUrl url ]


joinPaths : String -> String -> String
joinPaths base path =
    String.chopEnd "/" base ++ "/" ++ String.chopStart "/" path
