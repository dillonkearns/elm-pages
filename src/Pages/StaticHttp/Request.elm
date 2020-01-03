module Pages.StaticHttp.Request exposing (Request, hash)

import Json.Encode as Encode


type alias Request =
    { url : String
    , method : String
    , headers : List ( String, String )
    }


hash : Request -> String
hash requestDetails =
    Encode.object
        [ ( "method", Encode.string requestDetails.method )
        , ( "url", Encode.string requestDetails.url )
        , ( "headers", Encode.list hashHeader requestDetails.headers )
        ]
        |> Encode.encode 0


hashHeader : ( String, String ) -> Encode.Value
hashHeader ( name, value ) =
    Encode.string <| name ++ ": " ++ value
