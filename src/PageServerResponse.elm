module PageServerResponse exposing (PageServerResponse(..), Response, toJson, toRedirect)

import Dict
import Json.Encode
import List.Extra


type PageServerResponse data error
    = RenderPage
        { statusCode : Int
        , headers : List ( String, String )
        }
        data
    | ServerResponse Response
    | ErrorPage error { headers : List ( String, String ) }


toRedirect :
    { response
        | statusCode : Int
        , headers : List ( String, String )
    }
    -> Maybe { statusCode : Int, location : String }
toRedirect response =
    response.headers
        |> Dict.fromList
        |> Dict.get "Location"
        |> Maybe.andThen
            (\location ->
                if response.statusCode == 302 then
                    Just { statusCode = 302, location = location }

                else
                    Nothing
            )


type alias Response =
    { statusCode : Int
    , headers : List ( String, String )
    , body : Maybe String
    , isBase64Encoded : Bool
    }


toJson : Response -> Json.Encode.Value
toJson serverResponse =
    Json.Encode.object
        [ ( "body", serverResponse.body |> Maybe.map Json.Encode.string |> Maybe.withDefault Json.Encode.null )
        , ( "statusCode", serverResponse.statusCode |> Json.Encode.int )
        , ( "headers"
          , serverResponse.headers
                |> collectMultiValueHeaders
                |> List.map (Tuple.mapSecond (Json.Encode.list Json.Encode.string))
                |> Json.Encode.object
          )
        , ( "kind", Json.Encode.string "server-response" )
        , ( "isBase64Encoded", Json.Encode.bool serverResponse.isBase64Encoded )
        ]


collectMultiValueHeaders : List ( String, String ) -> List ( String, List String )
collectMultiValueHeaders headers =
    headers
        |> List.Extra.groupWhile
            (\( key1, _ ) ( key2, _ ) -> key1 == key2)
        |> List.map
            (\( ( key, firstValue ), otherValues ) ->
                ( key
                , firstValue
                    :: (otherValues |> List.map Tuple.second)
                )
            )
