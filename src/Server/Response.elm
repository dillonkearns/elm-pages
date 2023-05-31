module Server.Response exposing
    ( Response
    , render
    , map
    , errorPage, mapError
    , temporaryRedirect, permanentRedirect
    , json, plainText
    , emptyBody, body, bytesBody, base64Body
    , withHeader, withHeaders, withStatusCode, withSetCookieHeader
    , toJson
    )

{-|


## Responses

@docs Response


## Response's for Route Modules

In a server-rendered Route Module, you return a [`Response`](#Response). You'll typically want to return one of 3 types of Responses
from your Route Modules:

  - [`Server.Response.render`](#render) to render the current Route Module
  - [`Server.Response.errorPage`](#errorPage) to render an ErrorPage
  - [`Server.Response.temporaryRedirect`](#temporaryRedirect) to redirect to another page (the easiest way to build a redirect response is with `Route.redirectTo : Route -> Response data error`).

```
    import Server.Response as Response
    import Route

    data routeParams request =
        case loggedInUser request of
            Just user ->
                findProjectById routeParams.id user
                |> BackendTask.map
                    (\maybeProject ->
                        case maybeProject of
                            Just project ->
                                Response.render project

                            Nothing ->
                                Response.errorPage ErrorPage.notFound
                    )
            Nothing ->
                -- the generated module `Route` contains a high-level helper for returning a redirect `Response`
                Route.redirectTo Route.Login
```


## Render Responses

@docs render

@docs map


## Rendering Error Pages

@docs errorPage, mapError


## Redirects

@docs temporaryRedirect, permanentRedirect


## Response's for Server-Rendered ApiRoutes

When defining your [server-rendered `ApiRoute`'s (`ApiRoute.serverRender`)](ApiRoute#serverRender) in your `app/Api.elm` module,
you can send a low-level server Response. You can set a String body,
a list of headers, the status code, etc. The Server Response helpers like `json` and `temporaryRedirect` are just helpers for
building up those low-level Server Responses.

Render Responses are a little more special in the way they are connected to your elm-pages app. They allow you to render
the current Route Module. To do that, you'll need to pass along the `data` for your Route Module.

You can use `withHeader` and `withStatusCode` to customize either type of Response (Server Responses or Render Responses).


## Body

@docs json, plainText


## Custom Responses

@docs emptyBody, body, bytesBody, base64Body


## Amending Responses

@docs withHeader, withHeaders, withStatusCode, withSetCookieHeader


## Internals

@docs toJson

-}

import Base64
import Bytes exposing (Bytes)
import Json.Encode
import PageServerResponse exposing (PageServerResponse(..))
import Server.SetCookie as SetCookie exposing (SetCookie)


{-| -}
type alias Response data error =
    PageServerResponse data error


{-| Maps the `data` for a Render response. Usually not needed, but always good to have the option.
-}
map : (data -> mappedData) -> Response data error -> Response mappedData error
map mapFn pageServerResponse =
    case pageServerResponse of
        RenderPage response data ->
            RenderPage response (mapFn data)

        ServerResponse serverResponse ->
            ServerResponse serverResponse

        ErrorPage error response ->
            ErrorPage error response


{-| Maps the `error` for an ErrorPage response. Usually not needed, but always good to have the option.
-}
mapError : (errorPage -> mappedErrorPage) -> Response data errorPage -> Response data mappedErrorPage
mapError mapFn pageServerResponse =
    case pageServerResponse of
        RenderPage response data ->
            RenderPage response data

        ServerResponse serverResponse ->
            ServerResponse serverResponse

        ErrorPage error response ->
            ErrorPage (mapFn error) response


{-| Build a `Response` with a String body. Sets the `Content-Type` to `text/plain`.

    Response.plainText "Hello"

-}
plainText : String -> Response data error
plainText string =
    { statusCode = 200
    , headers = [ ( "Content-Type", "text/plain" ) ]
    , body = Just string
    , isBase64Encoded = False
    }
        |> ServerResponse


{-| Render the Route Module with the supplied data. Used for both the `data` and `action` functions in a server-rendered Route Module.

    Response.render project

-}
render : data -> Response data error
render data =
    RenderPage
        { statusCode = 200, headers = [] }
        data


{-| Instead of rendering the current Route Module, you can render an `ErrorPage` such as a 404 page or a 500 error page.

[Read more about Error Pages](https://elm-pages-v3.netlify.app/docs/error-pages) to learn about
defining and rendering your custom ErrorPage type.

-}
errorPage : errorPage -> Response data errorPage
errorPage errorPage_ =
    ErrorPage errorPage_ { headers = [] }


{-| Build a `Response` with no HTTP response body.
-}
emptyBody : Response data error
emptyBody =
    { statusCode = 200
    , headers = []
    , body = Nothing
    , isBase64Encoded = False
    }
        |> ServerResponse


{-| Same as [`plainText`](#plainText), but doesn't set a `Content-Type`.
-}
body : String -> Response data error
body body_ =
    { statusCode = 200
    , headers = []
    , body = Just body_
    , isBase64Encoded = False
    }
        |> ServerResponse


{-| Build a `Response` with a String that should represent a base64 encoded value.

Your adapter will need to handle `isBase64Encoded` to turn it into the appropriate response.

    Response.base64Body "SGVsbG8gV29ybGQ="

-}
base64Body : String -> Response data error
base64Body base64String =
    { statusCode = 200
    , headers = []
    , body = Just base64String
    , isBase64Encoded = True
    }
        |> ServerResponse


{-| Build a `Response` with a `Bytes`.

Under the hood, it will be converted to a base64 encoded String with `isBase64Encoded = True`.
Your adapter will need to handle `isBase64Encoded` to turn it into the appropriate response.

-}
bytesBody : Bytes -> Response data error
bytesBody bytes =
    { statusCode = 200
    , headers = []
    , body = bytes |> Base64.fromBytes
    , isBase64Encoded = True
    }
        |> ServerResponse


{-| Build a JSON body from a `Json.Encode.Value`.

    Json.Encode.object
        [ ( "message", Json.Encode.string "Hello" ) ]
        |> Response.json

Sets the `Content-Type` to `application/json`.

-}
json : Json.Encode.Value -> Response data error
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
permanentRedirect : String -> Response data error
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
temporaryRedirect : String -> Response data error
temporaryRedirect url =
    { body = Nothing
    , statusCode = 302
    , headers =
        [ ( "Location", url )
        ]
    , isBase64Encoded = False
    }
        |> ServerResponse


{-| Set the [HTTP Response status code](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status) for the `Response`.

    Response.plainText "Not Authorized"
        |> Response.withStatusCode 401

-}
withStatusCode : Int -> Response data Never -> Response data Never
withStatusCode statusCode serverResponse =
    case serverResponse of
        RenderPage response data ->
            RenderPage { response | statusCode = statusCode } data

        ServerResponse response ->
            ServerResponse { response | statusCode = statusCode }

        ErrorPage error _ ->
            never error


{-| Add a header to the response.

    Response.plainText "Hello!"
        -- allow CORS requests
        |> Response.withHeader "Access-Control-Allow-Origin" "*"
        |> Response.withHeader "Access-Control-Allow-Methods" "GET, POST, OPTIONS"

-}
withHeader : String -> String -> Response data error -> Response data error
withHeader name value serverResponse =
    case serverResponse of
        RenderPage response data ->
            RenderPage { response | headers = ( name, value ) :: response.headers } data

        ServerResponse response ->
            ServerResponse { response | headers = ( name, value ) :: response.headers }

        ErrorPage error response ->
            ErrorPage error { response | headers = ( name, value ) :: response.headers }


{-| Same as [`withHeader`](#withHeader), but allows you to add multiple headers at once.

    Response.plainText "Hello!"
        -- allow CORS requests
        |> Response.withHeaders
            [ ( "Access-Control-Allow-Origin", "*" )
            , ( "Access-Control-Allow-Methods", "GET, POST, OPTIONS" )
            ]

-}
withHeaders : List ( String, String ) -> Response data error -> Response data error
withHeaders headers serverResponse =
    case serverResponse of
        RenderPage response data ->
            RenderPage { response | headers = headers ++ response.headers } data

        ServerResponse response ->
            ServerResponse { response | headers = headers ++ response.headers }

        ErrorPage error response ->
            ErrorPage error { response | headers = headers ++ response.headers }


{-| Set a [`SetCookie`](SetCookie) value on the response.

The easiest way to manage cookies in your Routes is through the [`Server.Session`](Server-Session) API, but this
provides a more granular way to set cookies.

-}
withSetCookieHeader : SetCookie -> Response data error -> Response data error
withSetCookieHeader cookie response =
    response
        |> withHeader "Set-Cookie"
            (cookie
                |> SetCookie.toString
            )


{-| For internal use or more advanced use cases for meta frameworks.
-}
toJson : Response Never Never -> Json.Encode.Value
toJson response =
    case response of
        RenderPage _ data ->
            never data

        ServerResponse serverResponse ->
            PageServerResponse.toJson serverResponse

        ErrorPage error _ ->
            never error
