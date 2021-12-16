module DataSource.ServerRequest exposing
    ( ServerRequest, expectHeader, init, optionalHeader, staticData, toDataSource
    , Method(..), withAllHeaders, withHost, withMethod, withProtocol, withQueryParams
    )

{-|

@docs ServerRequest, expectHeader, init, optionalHeader, staticData, toDataSource

-}

import DataSource
import DataSource.Http
import Dict exposing (Dict)
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


{-| -}
toDataSource : ServerRequest decodesTo -> DataSource.DataSource decodesTo
toDataSource (ServerRequest decoder) =
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
