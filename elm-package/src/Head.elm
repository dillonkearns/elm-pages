module Head exposing (AttributeValue, Tag, canonicalLink, currentPageFullUrl, description, fullUrl, metaName, metaProperty, raw, toJson)

import Json.Encode
import Pages.Path as Path exposing (Path)


type Tag pathKey
    = Tag (Details pathKey)


type alias Details pathKey =
    { name : String
    , attributes : List ( String, AttributeValue pathKey )
    }


raw : String -> AttributeValue pathKey
raw value =
    Raw value


fullUrl : Path pathKey any -> AttributeValue pathKey
fullUrl value =
    FullUrl (Path.toString value)


currentPageFullUrl : AttributeValue pathKey
currentPageFullUrl =
    FullUrlToCurrentPage


type AttributeValue pathKey
    = Raw String
    | FullUrl String
    | FullUrlToCurrentPage


{-| Example:

    Head.canonicalLink "https://elm-pages.com"

-}
canonicalLink : Maybe (Path pathKey Path.ToPage) -> Tag pathKey
canonicalLink maybePath =
    node "link"
        [ ( "rel", raw "canonical" )
        , ( "href"
          , maybePath |> Maybe.map fullUrl |> Maybe.withDefault currentPageFullUrl
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


node : String -> List ( String, AttributeValue pathKey ) -> Tag pathKey
node name attributes =
    Tag
        { name = name
        , attributes = attributes
        }


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
