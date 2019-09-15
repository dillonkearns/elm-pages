module Head exposing
    ( Tag, AttributeValue, currentPageFullUrl, description, fullImageUrl, fullPageUrl, metaName, metaProperty, raw
    , toJson, canonicalLink
    )

{-|

@docs Tag, AttributeValue, currentPageFullUrl, description, fullImageUrl, fullPageUrl, metaName, metaProperty, raw


## Functions for use by generated code

@docs toJson, canonicalLink

-}

import Json.Encode
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)


type Tag pathKey
    = Tag (Details pathKey)


type alias Details pathKey =
    { name : String
    , attributes : List ( String, AttributeValue pathKey )
    }


raw : String -> AttributeValue pathKey
raw value =
    Raw value


fullImageUrl : ImagePath pathKey -> AttributeValue pathKey
fullImageUrl value =
    FullUrl (ImagePath.toString value)


fullPageUrl : PagePath pathKey -> AttributeValue pathKey
fullPageUrl value =
    FullUrl (PagePath.toString value)


currentPageFullUrl : AttributeValue pathKey
currentPageFullUrl =
    FullUrlToCurrentPage


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


{-| Example:

    metaProperty
        [ ( "property", "og:type" )
        , ( "content", "article" )
        ]

Results in `<meta property="og:type" content="article" />`

-}
metaProperty : String -> AttributeValue pathKey -> Tag pathKey
metaProperty property content =
    node "meta"
        [ ( "property", raw property )
        , ( "content", content )
        ]


description : String -> Tag pathKey
description descriptionValue =
    metaName "description" (raw descriptionValue)


{-| Example:

    metaName
        [ ( "name", "twitter:card" )
        , ( "content", "summary_large_image" )
        ]

Results in `<meta name="twitter:card" content="summary_large_image" />`

-}
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
