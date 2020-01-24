module Head exposing
    ( Tag, metaName, metaProperty
    , AttributeValue
    , currentPageFullUrl, fullImageUrl, fullPageUrl, raw
    , toJson, canonicalLink
    , rssLink
    )

{-| This module contains low-level functions for building up
values that will be rendered into the page's `<head>` tag
when you run `elm-pages build`. Most likely the `Head.Seo` module
will do everything you need out of the box, and you will just need to import `Head`
so you can use the `Tag` type in your type annotations.

But this module might be useful if you have a special use case, or if you are
writing a plugin package to extend `elm-pages`.

@docs Tag, metaName, metaProperty


## `AttributeValue`s

@docs AttributeValue
@docs currentPageFullUrl, fullImageUrl, fullPageUrl, raw


## Functions for use by generated code

@docs toJson, canonicalLink

-}

import Json.Encode
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)


{-| Values that can be passed to the generated `Pages.application` config
through the `head` function.
-}
type Tag pathKey
    = Tag (Details pathKey)


type alias Details pathKey =
    { name : String
    , attributes : List ( String, AttributeValue pathKey )
    }


{-| Create a raw `AttributeValue` (as opposed to some kind of absolute URL).
-}
raw : String -> AttributeValue pathKey
raw value =
    Raw value


{-| Create an `AttributeValue` from an `ImagePath`.
-}
fullImageUrl : ImagePath pathKey -> AttributeValue pathKey
fullImageUrl value =
    FullUrl (ImagePath.toString value)


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

```html
<link rel="alternate" type="application/rss+xml" href="/rss.xml">
```

Example:

    rssLink "/feed.xml"

-}
rssLink : String -> Tag pathKey
rssLink url =
    node "link"
        [ ( "rel", raw "alternate" )
        , ( "type", raw "application/rss+xml" )
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
toJson canonicalSiteUrl currentPagePath (Tag tag) =
    Json.Encode.object
        [ ( "name", Json.Encode.string tag.name )
        , ( "attributes", Json.Encode.list (encodeProperty canonicalSiteUrl currentPagePath) tag.attributes )
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


joinPaths : String -> String -> String
joinPaths base path =
    if (base |> String.endsWith "/") && (path |> String.startsWith "/") then
        base ++ String.dropLeft 1 path

    else
        base ++ path
