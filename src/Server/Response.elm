module Server.Response exposing
    ( Response
    , json, plainText, temporaryRedirect, permanentRedirect
    , customResponse, RawResponse
    , render
    , map
    , withHeader, withStatusCode
    , toJson
    )

{-|


## Responses

@docs Response

There are two top-level response types:

1.  Server Responses
2.  Render Responses

A Server Response is a way to directly send a low-level server response, with no additional magic. You can set a String body,
a list of headers, the status code, etc. The Server Response helpers like `json` and `temporaryRedirect` are just helpers for
building up those low-level Server Responses.

Render Responses are a little more special in the way they are connected to your elm-pages app. They allow you to render
the current Page Module. To do that, you'll need to pass along the `data` for your Page Module.

You can use `withHeader` and `withStatusCode` to customize either type of Response (Server Responses or Render Responses).


## Server Responses

@docs json, plainText, temporaryRedirect, permanentRedirect

@docs customResponse, RawResponse


## Render Responses

@docs render

@docs map


## Amending Responses

@docs withHeader, withStatusCode


## Internals

@docs toJson

-}

import Json.Encode
import PageServerResponse exposing (PageServerResponse(..))


{-| -}
type alias Response data =
    PageServerResponse data


{-| -}
type alias RawResponse =
    { statusCode : Int
    , headers : List ( String, String )
    , body : Maybe String
    , isBase64Encoded : Bool
    }


{-| -}
map : (data -> mappedData) -> PageServerResponse data -> PageServerResponse mappedData
map mapFn pageServerResponse =
    case pageServerResponse of
        RenderPage response data ->
            RenderPage response (mapFn data)

        ServerResponse serverResponse ->
            ServerResponse serverResponse


{-| -}
plainText : String -> Response data
plainText string =
    { statusCode = 200
    , headers = [ ( "Content-Type", "text/plain" ) ]
    , body = Just string
    , isBase64Encoded = False
    }
        |> ServerResponse


{-| -}
render : data -> PageServerResponse data
render data =
    RenderPage
        { statusCode = 200, headers = [] }
        data


{-| -}
customResponse : RawResponse -> Response data
customResponse rawResponse =
    ServerResponse rawResponse


{-| -}
json : Json.Encode.Value -> Response data
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
        |> ServerResponse


{-| Build a 308 permanent redirect response.

Permanent redirects tell the browser that a resource has permanently moved. If you redirect because a user is not logged in,
then you **do not** want to use a permanent redirect because the page they are looking for hasn't changed, you are just
temporarily pointing them to a new page since they need to authenticate.

Permanent redirects are aggressively cached so be careful not to use them when you mean to use temporary redirects instead.

If you need to specifically rely on a 301 permanent redirect (see <https://stackoverflow.com/a/42138726> on the difference between 301 and 308),
use `customResponse` instead.

-}
permanentRedirect : String -> Response data
permanentRedirect url =
    { body = Nothing
    , statusCode = 308
    , headers =
        [ ( "Location", url )
        ]
    , isBase64Encoded = False
    }
        |> ServerResponse


{-| -}
temporaryRedirect : String -> Response data
temporaryRedirect url =
    { body = Nothing
    , statusCode = 307
    , headers =
        [ ( "Location", url )
        ]
    , isBase64Encoded = False
    }
        |> ServerResponse


{-| -}
withStatusCode : Int -> Response data -> Response data
withStatusCode statusCode serverResponse =
    case serverResponse of
        RenderPage response data ->
            RenderPage { response | statusCode = statusCode } data

        ServerResponse response ->
            ServerResponse { response | statusCode = statusCode }


{-| -}
withHeader : String -> String -> Response data -> Response data
withHeader name value serverResponse =
    case serverResponse of
        RenderPage response data ->
            RenderPage { response | headers = ( name, value ) :: response.headers } data

        ServerResponse response ->
            ServerResponse { response | headers = ( name, value ) :: response.headers }


{-| -}
toJson : Response Never -> Json.Encode.Value
toJson response =
    case response of
        RenderPage _ data ->
            never data

        ServerResponse serverResponse ->
            PageServerResponse.toJson serverResponse
