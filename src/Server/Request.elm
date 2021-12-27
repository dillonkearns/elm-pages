module Server.Request exposing
    ( ServerRequest
    , Method(..)
    , init
    , Handler, Handlers, andMap, cookie, errorToString, expectCookie, expectFormField, expectQueryParam, getDecoder, map, map2, oneOf, oneOfHandler, requestTime, succeed, thenRespond, expectHeader, optionalHeader
    )

{-|

@docs ServerRequest

@docs Method

@docs init

@docs Handler, Handlers, andMap, cookie, errorToString, expectCookie, expectFormField, expectQueryParam, getDecoder, map, map2, oneOf, oneOfHandler, requestTime, succeed, thenRespond, expectHeader, optionalHeader

-}

import CookieParser
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import OptimizedDecoder
import PageServerResponse exposing (PageServerResponse)
import QueryParams exposing (QueryParams)
import Time


{-| -}
type ServerRequest decodesTo
    = ServerRequest (OptimizedDecoder.Decoder (Result ValidationError decodesTo))


oneOfInternal : List (OptimizedDecoder.Decoder (Result ValidationError decodesTo)) -> OptimizedDecoder.Decoder (Result ValidationError decodesTo)
oneOfInternal optimizedDecoders =
    case optimizedDecoders of
        [] ->
            OptimizedDecoder.fail "No more decoders"

        [ single ] ->
            single

        first :: rest ->
            first
                |> OptimizedDecoder.andThen
                    (\firstResult ->
                        case firstResult of
                            Ok okFirstResult ->
                                OptimizedDecoder.succeed (Ok okFirstResult)

                            Err error ->
                                oneOfInternal rest
                    )


{-| -}
succeed : value -> ServerRequest value
succeed value =
    ServerRequest (OptimizedDecoder.succeed (Ok value))


{-| -}
type Handlers data
    = Handlers (PageServerResponse data)


{-| -}
type Handler data
    = Handler (OptimizedDecoder.Decoder (Result ValidationError (DataSource (PageServerResponse data))))


{-| TODO internal only
-}
getDecoder : Handler data -> OptimizedDecoder.Decoder (Result ValidationError (DataSource (PageServerResponse data)))
getDecoder (Handler decoder) =
    decoder


{-| -}
thenRespond : (request -> DataSource (PageServerResponse data)) -> ServerRequest request -> Handler data
thenRespond thenDataSource (ServerRequest requestDecoder) =
    requestDecoder
        |> OptimizedDecoder.map (Result.map thenDataSource)
        |> Handler


type ValidationError
    = ValidationError String
      -- unexpected because violation of the contract - could be adapter issue, or issue with this package
    | InternalError


{-| TODO internal only
-}
errorToString : ValidationError -> String
errorToString validationError =
    case validationError of
        ValidationError message ->
            "ValidationError: \n" ++ message

        InternalError ->
            "InternalError"


{-| -}
init : constructor -> ServerRequest constructor
init constructor =
    ServerRequest (OptimizedDecoder.succeed (Ok constructor))


{-| -}
map : (a -> b) -> ServerRequest a -> ServerRequest b
map mapFn (ServerRequest decoder) =
    ServerRequest (OptimizedDecoder.map (Result.map mapFn) decoder)


{-| -}
oneOf : List (ServerRequest a) -> ServerRequest a
oneOf serverRequests =
    ServerRequest
        (oneOfInternal
            (List.map
                (\(ServerRequest decoder) -> decoder)
                serverRequests
            )
        )


{-| -}
oneOfHandler : List (Handler a) -> Handler a
oneOfHandler serverRequests =
    Handler
        (oneOfInternal
            (List.map
                (\(Handler decoder) -> decoder)
                serverRequests
            )
        )


{-| Decode an argument and provide it to a function in a decoder.

    decoder : Decoder String
    decoder =
        succeed (String.repeat)
            |> andMap (field "count" int)
            |> andMap (field "val" string)


    """ { "val": "hi", "count": 3 } """
        |> decodeString decoder
    --> Success "hihihi"

-}
andMap : ServerRequest a -> ServerRequest (a -> b) -> ServerRequest b
andMap =
    map2 (|>)


{-| -}
map2 : (a -> b -> c) -> ServerRequest a -> ServerRequest b -> ServerRequest c
map2 f (ServerRequest jdA) (ServerRequest jdB) =
    ServerRequest
        (OptimizedDecoder.map2 (Result.map2 f) jdA jdB)


{-| -}
expectHeader : String -> ServerRequest String
expectHeader headerName =
    OptimizedDecoder.optionalField (headerName |> String.toLower) OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> OptimizedDecoder.map (Result.fromMaybe InternalError)
        |> ServerRequest


{-| -}
requestTime : ServerRequest Time.Posix
requestTime =
    OptimizedDecoder.field "requestTime"
        (OptimizedDecoder.int |> OptimizedDecoder.map Time.millisToPosix)
        |> okOrInternalError
        |> ServerRequest


okOrInternalError : OptimizedDecoder.Decoder a -> OptimizedDecoder.Decoder (Result ValidationError a)
okOrInternalError decoder =
    OptimizedDecoder.maybe decoder
        |> OptimizedDecoder.map (Result.fromMaybe InternalError)


{-| -}
allHeaders : ServerRequest (Dict String String)
allHeaders =
    OptimizedDecoder.dict OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> okOrInternalError
        |> ServerRequest


{-| -}
method : ServerRequest Method
method =
    (OptimizedDecoder.field "method" OptimizedDecoder.string
        |> OptimizedDecoder.map methodFromString
    )
        |> okOrInternalError
        |> ServerRequest


{-| -}
acceptMethod : ( Method, List Method ) -> ServerRequest value -> ServerRequest value
acceptMethod ( accepted1, accepted ) (ServerRequest decoder) =
    (OptimizedDecoder.field "method" OptimizedDecoder.string
        |> OptimizedDecoder.map methodFromString
        |> OptimizedDecoder.andThen
            (\method_ ->
                if (accepted1 :: accepted) |> List.member method_ then
                    -- TODO distill here - is that possible???
                    decoder

                else
                    OptimizedDecoder.succeed (Err (ValidationError "Unexpected HTTP method"))
            )
    )
        |> ServerRequest


{-| -}
allQueryParams : ServerRequest QueryParams
allQueryParams =
    OptimizedDecoder.field "query" OptimizedDecoder.string
        |> OptimizedDecoder.map QueryParams.fromString
        |> okOrInternalError
        |> ServerRequest


{-| -}
queryParam : String -> ServerRequest (Maybe String)
queryParam name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "query"
        |> okOrInternalError
        |> ServerRequest


{-| -}
expectQueryParam : String -> ServerRequest String
expectQueryParam name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "query"
        |> OptimizedDecoder.map
            (\value ->
                case value of
                    Just justValue ->
                        Ok justValue

                    Nothing ->
                        Err (ValidationError ("Missing query param " ++ name))
            )
        |> ServerRequest


{-| -}
optionalHeader : String -> ServerRequest (Maybe String)
optionalHeader headerName =
    OptimizedDecoder.optionalField (headerName |> String.toLower) OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> okOrInternalError
        |> ServerRequest


{-| -}
allCookies : ServerRequest (Dict String String)
allCookies =
    OptimizedDecoder.optionalField "cookie" OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> OptimizedDecoder.map
            (\cookie_ ->
                cookie_
                    |> Maybe.withDefault ""
                    |> CookieParser.parse
            )
        |> okOrInternalError
        |> ServerRequest


{-| -}
expectCookie : String -> ServerRequest String
expectCookie name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "cookies"
        |> OptimizedDecoder.map
            (\value ->
                case value of
                    Just justValue ->
                        Ok justValue

                    Nothing ->
                        Err (ValidationError ("Missing cookie " ++ name))
            )
        |> ServerRequest


{-| -}
cookie : String -> ServerRequest (Maybe String)
cookie name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "cookies"
        |> okOrInternalError
        |> ServerRequest


{-| -}
expectFormField : String -> ServerRequest String
expectFormField name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "formData"
        |> OptimizedDecoder.map
            (\value ->
                case value of
                    Just justValue ->
                        Ok justValue

                    Nothing ->
                        Err (ValidationError ("Missing form field " ++ name))
            )
        |> ServerRequest


{-| -}
body : ServerRequest (Maybe String)
body =
    bodyDecoder
        |> okOrInternalError
        |> ServerRequest


bodyDecoder : OptimizedDecoder.Decoder (Maybe String)
bodyDecoder =
    OptimizedDecoder.field "body" (OptimizedDecoder.nullable OptimizedDecoder.string)


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
methodToString method_ =
    case method_ of
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
