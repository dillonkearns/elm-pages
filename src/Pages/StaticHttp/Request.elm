module Pages.StaticHttp.Request exposing (Request, hash)

import Json.Encode as Encode
import Pages.Internal.StaticHttpBody as StaticHttpBody exposing (Body)


type alias Request =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    }


hash : Request -> String
hash requestDetails =
    Encode.object
        [ ( "method", Encode.string requestDetails.method )
        , ( "url", Encode.string requestDetails.url )
        , ( "headers", Encode.list hashHeader requestDetails.headers )
        , ( "body", StaticHttpBody.encode requestDetails.body )
        ]
        |> Encode.encode 0


hashHeader : ( String, String ) -> Encode.Value
hashHeader ( name, value ) =
    Encode.string <| name ++ ": " ++ value
