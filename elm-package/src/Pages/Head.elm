module Pages.Head exposing (Tag, node, toJson)

import Json.Encode


type Tag
    = Tag Details


type alias Details =
    { name : String
    , attributes : List ( String, String )
    }


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
