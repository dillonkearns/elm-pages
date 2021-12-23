module DataSource.ServerRequest exposing
    ( IsAvailable
    , ServerRequest, expectHeader, init, optionalHeader, staticData, toDataSource, withFormData, withCookies, withBody, withHost, withAllHeaders, withMethod, withProtocol, Method(..), withQueryParams
    )

{-|

@docs IsAvailable

@docs ServerRequest, expectHeader, init, optionalHeader, staticData, toDataSource, withFormData, withCookies, withBody, withHost, withAllHeaders, withMethod, withProtocol, Method, withQueryParams

-}

import CookieParser
import DataSource
import DataSource.Http
import Dict exposing (Dict)
import FormData
import Internal.ServerRequest
import OptimizedDecoder
import QueryParams exposing (QueryParams)
import Secrets
import Url


{-| -}
type ServerRequest decodesTo
    = ServerRequest (OptimizedDecoder.Decoder decodesTo)


{-| -}
init : constructor -> ServerRequest constructor
init constructor =
    ServerRequest (OptimizedDecoder.succeed constructor)


{-| -}
staticData : DataSource.DataSource String
staticData =
    DataSource.Http.get (Secrets.succeed "$$elm-pages$$headers")
        (OptimizedDecoder.field "headers"
            (OptimizedDecoder.field "accept-language" OptimizedDecoder.string)
        )


{-| In order to access the ServerRequest data, you first need to turn it into a DataSource.

Note that you can only access it in the context of a serverless request because there is no request
to access for pre-rendered pages (requests are when a user hits a page, but pre-rendering happens before
users try to access your page, that's what the "pre-" part means).

The `IsAvailable` argument gives you a compile-time guarantee that you won't accidentally try to
access ServerRequest data in a context where it won't be available, so you can safely use this if you
have an `IsAvailable` value.

-}
toDataSource : IsAvailable -> ServerRequest decodesTo -> DataSource.DataSource decodesTo
toDataSource _ (ServerRequest decoder) =
    DataSource.Http.get (Secrets.succeed "$$elm-pages$$headers") decoder


{-| -}
expectHeader : String -> ServerRequest (String -> value) -> ServerRequest value
expectHeader headerName (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.field (headerName |> String.toLower) OptimizedDecoder.string
                |> OptimizedDecoder.field "headers"
            )
        |> ServerRequest


{-| -}
withAllHeaders : ServerRequest (Dict String String -> value) -> ServerRequest value
withAllHeaders (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.dict OptimizedDecoder.string
                |> OptimizedDecoder.field "headers"
            )
        |> ServerRequest


{-| -}
withMethod : ServerRequest (Method -> value) -> ServerRequest value
withMethod (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.field "method" OptimizedDecoder.string
                |> OptimizedDecoder.map methodFromString
            )
        |> ServerRequest


{-| -}
withHost : ServerRequest (String -> value) -> ServerRequest value
withHost (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.field "host" OptimizedDecoder.string)
        |> ServerRequest


{-| -}
withProtocol : ServerRequest (Url.Protocol -> value) -> ServerRequest value
withProtocol (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.field "protocol" OptimizedDecoder.string
                |> OptimizedDecoder.andThen
                    (\protocol ->
                        if protocol |> String.startsWith "https" then
                            OptimizedDecoder.succeed Url.Https

                        else if protocol |> String.startsWith "http" then
                            OptimizedDecoder.succeed Url.Http

                        else
                            OptimizedDecoder.fail <| "Unexpected protocol: " ++ protocol
                    )
            )
        |> ServerRequest


{-| -}
withQueryParams : ServerRequest (QueryParams -> value) -> ServerRequest value
withQueryParams (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.field "query" OptimizedDecoder.string
                |> OptimizedDecoder.map QueryParams.fromString
            )
        |> ServerRequest


{-| -}
optionalHeader : String -> ServerRequest (Maybe String -> value) -> ServerRequest value
optionalHeader headerName (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.optionalField (headerName |> String.toLower) OptimizedDecoder.string
                |> OptimizedDecoder.field "headers"
            )
        |> ServerRequest


{-| -}
withCookies : ServerRequest (Dict String String -> value) -> ServerRequest value
withCookies (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.optionalField "cookie" OptimizedDecoder.string
                |> OptimizedDecoder.field "headers"
                |> OptimizedDecoder.map
                    (\cookie ->
                        cookie
                            |> Maybe.withDefault ""
                            |> CookieParser.parse
                    )
            )
        |> ServerRequest


{-| -}
withBody : ServerRequest (Maybe String -> value) -> ServerRequest value
withBody (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.optionalField "body" OptimizedDecoder.string)
        |> ServerRequest


{-| -}
withFormData :
    ServerRequest
        (Maybe (Dict String ( String, List String ))
         -> value
        )
    -> ServerRequest value
withFormData (ServerRequest decoder) =
    decoder
        |> OptimizedDecoder.andMap
            (OptimizedDecoder.map2
                (\contentType maybeBody ->
                    -- TODO parse content-type more robustly
                    if contentType == Just "application/x-www-form-urlencoded" then
                        maybeBody
                            |> Maybe.map FormData.parse

                    else
                        Nothing
                )
                (OptimizedDecoder.optionalField
                    ("content-type"
                        |> String.toLower
                    )
                    OptimizedDecoder.string
                    |> OptimizedDecoder.field "headers"
                )
                (OptimizedDecoder.optionalField "body" OptimizedDecoder.string)
            )
        |> ServerRequest


{-| -}
type Method
    = Connect
    | Delete
    | Get
    | Head
    | Options
    | Patch
    | Post
    | Put
    | Trace
    | NonStandard String


methodFromString : String -> Method
methodFromString rawMethod =
    case rawMethod |> String.toLower of
        "connect" ->
            Connect

        "delete" ->
            Delete

        "get" ->
            Get

        "head" ->
            Head

        "options" ->
            Options

        "patch" ->
            Patch

        "post" ->
            Post

        "put" ->
            Put

        "trace" ->
            Trace

        _ ->
            NonStandard rawMethod


{-| Gets the HTTP Method as a String, like 'GET', 'PUT', etc.
-}
methodToString : Method -> String
methodToString method =
    case method of
        Connect ->
            "CONNECT"

        Delete ->
            "DELETE"

        Get ->
            "GET"

        Head ->
            "HEAD"

        Options ->
            "OPTIONS"

        Patch ->
            "PATCH"

        Post ->
            "POST"

        Put ->
            "PUT"

        Trace ->
            "TRACE"

        NonStandard nonStandardMethod ->
            nonStandardMethod


{-| This will be passed in wherever it's possible to access the DataSource.ServerRequest, like in a serverless request. This data, like the query params or incoming request headers,
do not exist for pre-rendered pages since they are not responding to a user request. They are built in advance. This value ensures that the compiler will make sure you can only use
the DataSource.ServerRequest API when it will actually be there for you to use.
-}
type alias IsAvailable =
    Internal.ServerRequest.IsAvailable
