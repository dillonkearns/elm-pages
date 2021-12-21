module ServerResponse exposing (ServerResponse, json, permanentRedirect, stringBody, success)

import Json.Encode


type alias ServerResponse =
    { statusCode : Int
    , headers : List ( String, String )
    , body : Maybe String
    , isBase64Encoded : Bool
    }


stringBody : String -> ServerResponse
stringBody string =
    { statusCode = 200
    , headers = [ ( "Content-Type", "text/plain" ) ]
    , body = Just string
    , isBase64Encoded = False
    }


success : ServerResponse
success =
    { statusCode = 200
    , headers = []
    , body = Nothing
    , isBase64Encoded = False
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
    , isBase64Encoded = False
    }


permanentRedirect : String -> ServerResponse
permanentRedirect url =
    { body = Nothing
    , statusCode = 308
    , headers =
        [ ( "Location", url )
        ]
    , isBase64Encoded = False
    }
