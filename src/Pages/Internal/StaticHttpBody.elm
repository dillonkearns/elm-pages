module Pages.Internal.StaticHttpBody exposing (Body(..), encode)

import Json.Encode as Encode


type Body
    = EmptyBody
    | StringBody String String
    | JsonBody Encode.Value


encode : Body -> Encode.Value
encode body =
    case body of
        EmptyBody ->
            encodeWithType "empty" []

        StringBody contentType content ->
            encodeWithType "string"
                [ ( "content", Encode.string content )
                ]

        JsonBody content ->
            encodeWithType "json"
                [ ( "content", content )
                ]


encodeWithType typeName otherFields =
    Encode.object <|
        ( "type", Encode.string typeName )
            :: otherFields
