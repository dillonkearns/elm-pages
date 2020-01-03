module Pages.StaticHttp.Body exposing (Body, empty, encode, string)

import Json.Encode as Encode


empty : Body
empty =
    EmptyBody


string : String -> Body
string content =
    StringBody content


type Body
    = EmptyBody
    | StringBody String


encode : Body -> Encode.Value
encode body =
    case body of
        EmptyBody ->
            encodeWithType "empty" []

        StringBody content ->
            encodeWithType "string"
                [ ( "content", Encode.string content )
                ]


encodeWithType typeName otherFields =
    Encode.object <|
        ( "type", Encode.string typeName )
            :: otherFields
