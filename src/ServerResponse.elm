module ServerResponse exposing (ServerResponse, json, permanentRedirect, stringBody, success, temporaryRedirect, toJson, withStatusCode)

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


temporaryRedirect : String -> ServerResponse
temporaryRedirect url =
    { body = Nothing
    , statusCode = 307
    , headers =
        [ ( "Location", url )
        ]
    , isBase64Encoded = False
    }


withStatusCode : Int -> ServerResponse -> ServerResponse
withStatusCode statusCode serverResponse =
    { serverResponse | statusCode = statusCode }


toJson : ServerResponse -> Json.Encode.Value
toJson serverResponse =
    Json.Encode.object
        [ ( "body", serverResponse.body |> Maybe.map Json.Encode.string |> Maybe.withDefault Json.Encode.null )
        , ( "statusCode", serverResponse.statusCode |> Json.Encode.int )
        , ( "headers"
          , serverResponse.headers
                |> List.map (Tuple.mapSecond Json.Encode.string)
                |> Json.Encode.object
          )
        , ( "kind", Json.Encode.string "server-response" )
        , ( "isBase64Encoded", Json.Encode.bool serverResponse.isBase64Encoded )
        ]
