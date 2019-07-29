module Pages.HeadTag exposing (HeadTag(..), node, toJson)

import Json.Encode


type HeadTag
    = HeadTag Details


type alias Details =
    { name : String
    , attributes : List ( String, String )
    }


node : String -> List ( String, String ) -> HeadTag
node name attributes =
    HeadTag
        { name = name
        , attributes = attributes
        }


toJson : HeadTag -> Json.Encode.Value
toJson (HeadTag tag) =
    Json.Encode.object
        [ ( "name", Json.Encode.string tag.name )
        , ( "attributes", Json.Encode.list encodeProperty tag.attributes )
        ]


encodeProperty : ( String, String ) -> Json.Encode.Value
encodeProperty ( name, value ) =
    Json.Encode.list Json.Encode.string [ name, value ]
