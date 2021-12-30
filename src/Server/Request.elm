module Server.Request exposing
    ( ServerRequest(..)
    , Method(..)
    , succeed
    , Handler, Handlers
    , oneOfHandler, requestTime, thenRespond, optionalHeader, expectContentType, expectJsonBody, acceptMethod
    , map, map2, oneOf, andMap
    , expectQueryParam
    , cookie, expectCookie
    , expectHeader
    , expectFormPost
    , File, expectMultiPartFormPost
    , errorToString, getDecoder
    , methodToString
    )

{-|

@docs ServerRequest

@docs Method

@docs succeed

@docs Handler, Handlers

@docs oneOfHandler, requestTime, thenRespond, optionalHeader, expectContentType, expectJsonBody, acceptMethod


## Transforming

@docs map, map2, oneOf, andMap


## Query Parameters

@docs expectQueryParam


## Cookies

@docs cookie, expectCookie


## Headers

@docs expectHeader


## Form Posts

@docs expectFormPost


## Multi-part forms and file uploads

@docs File, expectMultiPartFormPost


## Internals

@docs errorToString, getDecoder

-}

import CookieParser
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Json.Decode
import OptimizedDecoder
import QueryParams exposing (QueryParams)
import Time


{-| -}
type ServerRequest decodesTo
    = ServerRequest (OptimizedDecoder.Decoder (Result ValidationError decodesTo))


oneOfInternal : List ValidationError -> List (OptimizedDecoder.Decoder (Result ValidationError decodesTo)) -> OptimizedDecoder.Decoder (Result ValidationError decodesTo)
oneOfInternal previousErrors optimizedDecoders =
    case optimizedDecoders of
        [] ->
            OptimizedDecoder.succeed (Err (OneOf previousErrors))

        [ single ] ->
            single
                |> OptimizedDecoder.map
                    (\result ->
                        result
                            |> Result.mapError (\error -> OneOf (previousErrors ++ [ error ]))
                    )

        first :: rest ->
            first
                |> OptimizedDecoder.andThen
                    (\firstResult ->
                        case firstResult of
                            Ok okFirstResult ->
                                OptimizedDecoder.succeed (Ok okFirstResult)

                            Err error ->
                                case error of
                                    OneOf errors ->
                                        oneOfInternal (previousErrors ++ errors) rest

                                    _ ->
                                        oneOfInternal (error :: previousErrors) rest
                    )


{-| -}
succeed : value -> ServerRequest value
succeed value =
    ServerRequest (OptimizedDecoder.succeed (Ok value))


{-| -}
type Handlers response
    = Handlers response


{-| -}
type Handler response
    = Handler (OptimizedDecoder.Decoder (Result ValidationError (DataSource response)))


{-| TODO internal only
-}
getDecoder : Handler response -> OptimizedDecoder.Decoder (Result ValidationError (DataSource response))
getDecoder (Handler decoder) =
    decoder


{-| -}
thenRespond : (request -> DataSource response) -> ServerRequest request -> Handler response
thenRespond thenDataSource (ServerRequest requestDecoder) =
    requestDecoder
        |> OptimizedDecoder.map (Result.map thenDataSource)
        |> Handler


type ValidationError
    = ValidationError String
    | OneOf (List ValidationError)
      -- unexpected because violation of the contract - could be adapter issue, or issue with this package
    | InternalError
    | JsonDecodeError Json.Decode.Error


{-| TODO internal only
-}
errorToString : ValidationError -> String
errorToString validationError =
    case validationError of
        ValidationError message ->
            message

        InternalError ->
            "InternalError"

        JsonDecodeError error ->
            "Unable to parse JSON body\n" ++ Json.Decode.errorToString error

        OneOf validationErrors ->
            "Server.Request.oneOf failed in the following "
                ++ String.fromInt (List.length validationErrors)
                ++ " ways:\n\n"
                ++ (validationErrors
                        |> List.indexedMap (\index error -> "(" ++ String.fromInt (index + 1) ++ ") " ++ errorToString error)
                        |> String.join "\n\n"
                   )


{-| -}
map : (a -> b) -> ServerRequest a -> ServerRequest b
map mapFn (ServerRequest decoder) =
    ServerRequest (OptimizedDecoder.map (Result.map mapFn) decoder)


{-| -}
oneOf : List (ServerRequest a) -> ServerRequest a
oneOf serverRequests =
    ServerRequest
        (oneOfInternal []
            (List.map
                (\(ServerRequest decoder) -> decoder)
                serverRequests
            )
        )


{-| -}
oneOfHandler : List (Handler a) -> Handler a
oneOfHandler serverRequests =
    Handler
        (oneOfInternal []
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
                    OptimizedDecoder.succeed
                        (Err
                            (ValidationError
                                ("Expected HTTP method " ++ String.join ", " ((accepted1 :: accepted) |> List.map methodToString) ++ " but was " ++ methodToString method_)
                            )
                        )
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
                        Err (ValidationError ("Missing query param \"" ++ name ++ "\""))
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


formField_ : String -> ServerRequest String
formField_ name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.map
            (\value ->
                case value of
                    Just justValue ->
                        Ok justValue

                    Nothing ->
                        Err (ValidationError ("Missing form field " ++ name))
            )
        |> ServerRequest


optionalFormField_ : String -> ServerRequest (Maybe String)
optionalFormField_ name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> okOrInternalError
        |> ServerRequest


{-| -}
type alias File =
    { name : String
    , mimeType : String
    , body : String
    }


fileField_ : String -> ServerRequest File
fileField_ name =
    OptimizedDecoder.optionalField name
        (OptimizedDecoder.oneOf
            [ OptimizedDecoder.map3 File
                (OptimizedDecoder.field "filename" OptimizedDecoder.string)
                (OptimizedDecoder.field "mimeType" OptimizedDecoder.string)
                (OptimizedDecoder.field "body" OptimizedDecoder.string)
            ]
        )
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
expectFormPost :
    ({ field : String -> ServerRequest String
     , optionalField : String -> ServerRequest (Maybe String)
     }
     -> ServerRequest decodedForm
    )
    -> ServerRequest decodedForm
expectFormPost toForm =
    map2 (\_ value -> value)
        (expectContentType "application/x-www-form-urlencoded")
        (toForm { field = formField_, optionalField = optionalFormField_ }
            |> (\(ServerRequest decoder) -> decoder)
            |> OptimizedDecoder.field "formData"
            |> ServerRequest
            |> acceptMethod ( Post, [] )
        )


{-| -}
expectMultiPartFormPost :
    ({ field : String -> ServerRequest String
     , optionalField : String -> ServerRequest (Maybe String)
     , fileField : String -> ServerRequest File
     }
     -> ServerRequest decodedForm
    )
    -> ServerRequest decodedForm
expectMultiPartFormPost toForm =
    map2 (\_ value -> value)
        (expectContentType "multipart/form-data")
        (toForm
            { field = formField_
            , optionalField = optionalFormField_
            , fileField = fileField_
            }
            |> (\(ServerRequest decoder) -> decoder)
            |> OptimizedDecoder.field "multiPartFormData"
            |> ServerRequest
            |> acceptMethod ( Post, [] )
        )


{-| -}
body : ServerRequest (Maybe String)
body =
    bodyDecoder
        |> okOrInternalError
        |> ServerRequest


{-| -}
expectContentType : String -> ServerRequest ()
expectContentType expectedContentType =
    OptimizedDecoder.optionalField ("content-type" |> String.toLower) OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> OptimizedDecoder.map
            (\maybeContentType ->
                case maybeContentType of
                    Nothing ->
                        Err (ValidationError "Missing content-type")

                    Just contentType ->
                        if (contentType |> parseContentType) == (expectedContentType |> parseContentType) then
                            Ok ()

                        else
                            Err (ValidationError ("Expected content-type to be " ++ expectedContentType ++ " but it was " ++ contentType))
            )
        |> ServerRequest


parseContentType : String -> String
parseContentType rawContentType =
    rawContentType
        |> String.split ";"
        |> List.head
        |> Maybe.withDefault rawContentType


{-| -}
expectJsonBody : OptimizedDecoder.Decoder value -> ServerRequest value
expectJsonBody jsonBodyDecoder =
    map2 (\() secondValue -> secondValue)
        (expectContentType "application/json")
        (OptimizedDecoder.oneOf
            [ OptimizedDecoder.field "jsonBody" jsonBodyDecoder
                |> OptimizedDecoder.map Ok
            , OptimizedDecoder.field "jsonBody" OptimizedDecoder.value
                |> OptimizedDecoder.map
                    (OptimizedDecoder.decodeValue jsonBodyDecoder)
                |> OptimizedDecoder.map (Result.mapError JsonDecodeError)
            ]
            |> ServerRequest
        )


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
