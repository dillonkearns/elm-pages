module Head exposing (Tag, canonicalLink, description, metaName, metaProperty, toJson)

import Json.Encode


type Tag
    = Tag Details


type alias Details =
    { name : String
    , attributes : List ( String, String )
    }


{-| Example:

    Head.canonicalLink "https://elm-pages.com"

-}
canonicalLink url =
    node "link"
        [ ( "rel", "canonical" )
        , ( "href", url )
        ]


{-| Example:

    metaProperty
        [ ( "property", "og:type" )
        , ( "content", "article" )
        ]

Results in `<meta property="og:type" content="article" />`

-}
metaProperty property content =
    node "meta"
        [ ( "property", property )
        , ( "content", content )
        ]


description descriptionValue =
    metaName "description" descriptionValue


{-| Example:

    metaName
        [ ( "name", "twitter:card" )
        , ( "content", "summary_large_image" )
        ]

Results in `<meta name="twitter:card" content="summary_large_image" />`

-}
metaName name content =
    node "meta"
        [ ( "name", name )
        , ( "content", content )
        ]


node : String -> List ( String, String ) -> Tag
node name attributes =
    Tag
        { name = name
        , attributes = attributes
        }


toJson : Tag -> Json.Encode.Value
toJson (Tag tag) =
    Json.Encode.object
        [ ( "name", Json.Encode.string tag.name )
        , ( "attributes", Json.Encode.list encodeProperty tag.attributes )
        ]


encodeProperty : ( String, String ) -> Json.Encode.Value
encodeProperty ( name, value ) =
    Json.Encode.list Json.Encode.string [ name, value ]
