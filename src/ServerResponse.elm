module ServerResponse exposing (ServerResponse, json, permanentRedirect, success)

import Json.Encode


type alias ServerResponse =
    { statusCode : Int
    , headers : List ( String, String )
    , body : Maybe String
    }


success : ServerResponse
success =
    { statusCode = 200
    , headers = []
    , body = Nothing
    }


json : Json.Encode.Value -> ServerResponse
json jsonValue =
    { statusCode = 200
    , headers =
        [ ( "Content-Type", "application/json" )
        ]
    , body =
        jsonValue
            |> Json.Encode.encode 0
            |> Just
    }


permanentRedirect : String -> ServerResponse
permanentRedirect url =
    { body = Nothing
    , statusCode = 308
    , headers =
        [ ( "Location", url )
        ]
    }
