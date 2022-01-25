module Server.Request exposing
    ( Request(..)
    , Method(..), methodToString
    , succeed
    , requestTime, optionalHeader, expectContentType, expectJsonBody, jsonBodyResult
    , acceptMethod, acceptContentTypes
    , map, map2, oneOf, andMap
    , expectQueryParam
    , cookie, expectCookie
    , expectHeader
    , expectFormPost
    , File, expectMultiPartFormPost
    , errorsToString, errorToString, getDecoder
    , andThen
    )

{-|

@docs Request

@docs Method, methodToString

@docs succeed

@docs requestTime, optionalHeader, expectContentType, expectJsonBody, jsonBodyResult

@docs acceptMethod, acceptContentTypes


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

@docs errorsToString, errorToString, getDecoder

-}

import CookieParser
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Json.Decode
import List.NonEmpty
import OptimizedDecoder exposing (Decoder)
import QueryParams exposing (QueryParams)
import Time


{-| -}
type Request decodesTo
    = Request (OptimizedDecoder.Decoder ( Result ValidationError decodesTo, List ValidationError ))


oneOfInternal : List ValidationError -> List (OptimizedDecoder.Decoder ( Result ValidationError decodesTo, List ValidationError )) -> OptimizedDecoder.Decoder ( Result ValidationError decodesTo, List ValidationError )
oneOfInternal previousErrors optimizedDecoders =
    case optimizedDecoders of
        [] ->
            OptimizedDecoder.succeed ( Err (OneOf previousErrors), [] )

        [ single ] ->
            single
                |> OptimizedDecoder.map
                    (\result ->
                        result
                            |> Tuple.mapFirst (Result.mapError (\error -> OneOf (previousErrors ++ [ error ])))
                    )

        first :: rest ->
            OptimizedDecoder.oneOf
                [ first
                    |> OptimizedDecoder.andThen
                        (\( firstResult, firstErrors ) ->
                            case ( firstResult, firstErrors ) of
                                ( Ok okFirstResult, [] ) ->
                                    OptimizedDecoder.succeed ( Ok okFirstResult, [] )

                                ( Ok okFirstResult, otherErrors ) ->
                                    oneOfInternal (previousErrors ++ otherErrors) rest

                                ( Err error, otherErrors ) ->
                                    case error of
                                        OneOf errors ->
                                            oneOfInternal (previousErrors ++ errors) rest

                                        _ ->
                                            oneOfInternal (previousErrors ++ [ error ]) rest
                        )
                ]


{-| -}
succeed : value -> Request value
succeed value =
    Request (OptimizedDecoder.succeed ( Ok value, [] ))


{-| TODO internal only
-}
getDecoder : Request (DataSource response) -> OptimizedDecoder.Decoder (Result ( ValidationError, List ValidationError ) (DataSource response))
getDecoder (Request decoder) =
    decoder
        |> OptimizedDecoder.map
            (\( result, validationErrors ) ->
                case ( result, validationErrors ) of
                    ( Ok value, [] ) ->
                        value
                            |> Ok

                    ( Ok _, firstError :: rest ) ->
                        Err ( firstError, rest )

                    ( Err fatalError, errors ) ->
                        Err ( fatalError, errors )
            )


type ValidationError
    = ValidationError String
    | OneOf (List ValidationError)
      -- unexpected because violation of the contract - could be adapter issue, or issue with this package
    | InternalError
    | JsonDecodeError Json.Decode.Error
    | NotFormPost { method : Maybe Method, contentType : Maybe String }


{-| -}
errorsToString : ( ValidationError, List ValidationError ) -> String
errorsToString validationErrors =
    validationErrors
        |> List.NonEmpty.toList
        |> List.map errorToString
        |> String.join "\n"


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

        NotFormPost record ->
            "Did not match formPost because\n"
                ++ ([ record.method
                        |> Maybe.map (\method_ -> "- Form post must have method POST, but the method was " ++ methodToString method_)
                    , record.contentType |> Maybe.map (\contentType -> "- Forms must have Content-Type application/x-www-form-urlencoded, but the Content-Type was " ++ contentType)
                    ]
                        |> List.filterMap identity
                        |> String.join "\n"
                   )


{-| -}
map : (a -> b) -> Request a -> Request b
map mapFn (Request decoder) =
    Request
        (OptimizedDecoder.map
            (\( result, errors ) ->
                ( Result.map mapFn result, errors )
            )
            decoder
        )


{-| -}
oneOf : List (Request a) -> Request a
oneOf serverRequests =
    Request
        (oneOfInternal []
            (List.map
                (\(Request decoder) -> decoder)
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
andMap : Request a -> Request (a -> b) -> Request b
andMap =
    map2 (|>)


andThen : (a -> Request b) -> Request a -> Request b
andThen toRequestB (Request requestA) =
    OptimizedDecoder.andThen
        (\value ->
            case value of
                ( Ok okValue, errors ) ->
                    okValue
                        |> toRequestB
                        |> unwrap

                ( Err error, errors ) ->
                    OptimizedDecoder.succeed ( Err error, errors )
        )
        requestA
        |> Request


unwrap : Request a -> Decoder ( Result ValidationError a, List ValidationError )
unwrap (Request decoder_) =
    decoder_


{-| -}
map2 : (a -> b -> c) -> Request a -> Request b -> Request c
map2 f (Request jdA) (Request jdB) =
    Request
        (OptimizedDecoder.map2
            (\( result1, errors1 ) ( result2, errors2 ) ->
                ( Result.map2 f result1 result2
                , errors1 ++ errors2
                )
            )
            jdA
            jdB
        )


{-| -}
expectHeader : String -> Request String
expectHeader headerName =
    OptimizedDecoder.optionalField (headerName |> String.toLower) OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> OptimizedDecoder.andThen (\value -> OptimizedDecoder.fromResult (value |> Result.fromMaybe "Missing field headers"))
        |> noErrors
        |> Request


{-| -}
requestTime : Request Time.Posix
requestTime =
    OptimizedDecoder.field "requestTime"
        (OptimizedDecoder.int |> OptimizedDecoder.map Time.millisToPosix)
        |> noErrors
        |> Request


okOrInternalError : OptimizedDecoder.Decoder a -> OptimizedDecoder.Decoder (Result ValidationError a)
okOrInternalError decoder =
    OptimizedDecoder.maybe decoder
        |> OptimizedDecoder.map (Result.fromMaybe InternalError)


{-| -}
method : Request Method
method =
    (OptimizedDecoder.field "method" OptimizedDecoder.string
        |> OptimizedDecoder.map methodFromString
    )
        |> noErrors
        |> Request


noErrors : OptimizedDecoder.Decoder value -> OptimizedDecoder.Decoder ( Result ValidationError value, List ValidationError )
noErrors decoder =
    decoder
        |> OptimizedDecoder.map (\value -> ( Ok value, [] ))


{-| -}
acceptContentTypes : ( String, List String ) -> Request value -> Request value
acceptContentTypes ( accepted1, accepted ) (Request decoder) =
    -- TODO this should parse content-types so it doesn't need to be an exact match (support `; q=...`, etc.)
    OptimizedDecoder.optionalField ("Accept" |> String.toLower) OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> OptimizedDecoder.andThen
            (\acceptHeader ->
                if List.NonEmpty.fromCons accepted1 accepted |> List.NonEmpty.member (acceptHeader |> Maybe.withDefault "") then
                    decoder

                else
                    decoder
                        |> appendError
                            (ValidationError
                                ("Expected Accept header " ++ String.join ", " (accepted1 :: accepted) ++ " but was " ++ (acceptHeader |> Maybe.withDefault ""))
                            )
            )
        |> Request


{-| -}
acceptMethod : ( Method, List Method ) -> Request value -> Request value
acceptMethod ( accepted1, accepted ) (Request decoder) =
    (OptimizedDecoder.field "method" OptimizedDecoder.string
        |> OptimizedDecoder.map methodFromString
        |> OptimizedDecoder.andThen
            (\method_ ->
                if (accepted1 :: accepted) |> List.member method_ then
                    -- TODO distill here - is that possible???
                    decoder

                else
                    decoder
                        |> appendError
                            (ValidationError
                                ("Expected HTTP method " ++ String.join ", " ((accepted1 :: accepted) |> List.map methodToString) ++ " but was " ++ methodToString method_)
                            )
            )
    )
        |> Request


{-| -}
matchesMethod : ( Method, List Method ) -> Request Bool
matchesMethod ( accepted1, accepted ) =
    (OptimizedDecoder.field "method" OptimizedDecoder.string
        |> OptimizedDecoder.map methodFromString
        |> OptimizedDecoder.map
            (\method_ ->
                (accepted1 :: accepted) |> List.member method_
            )
    )
        |> noErrors
        |> Request


appendError : ValidationError -> OptimizedDecoder.Decoder ( value, List ValidationError ) -> OptimizedDecoder.Decoder ( value, List ValidationError )
appendError error decoder =
    decoder
        |> OptimizedDecoder.map (Tuple.mapSecond (\errors -> error :: errors))


{-| -}
allQueryParams : Request QueryParams
allQueryParams =
    OptimizedDecoder.field "query" OptimizedDecoder.string
        |> OptimizedDecoder.map QueryParams.fromString
        |> noErrors
        |> Request


{-| -}
queryParam : String -> Request (Maybe String)
queryParam name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "query"
        |> noErrors
        |> Request


{-| -}
expectQueryParam : String -> Request String
expectQueryParam name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "query"
        |> OptimizedDecoder.map
            (\value ->
                case value of
                    Just justValue ->
                        ( Ok justValue, [] )

                    Nothing ->
                        ( Err (ValidationError ("Missing query param \"" ++ name ++ "\"")), [] )
            )
        |> Request


{-| -}
optionalHeader : String -> Request (Maybe String)
optionalHeader headerName =
    OptimizedDecoder.optionalField (headerName |> String.toLower) OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> noErrors
        |> Request


{-| -}
allCookies : Request (Dict String String)
allCookies =
    OptimizedDecoder.optionalField "cookie" OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> OptimizedDecoder.map
            (\cookie_ ->
                cookie_
                    |> Maybe.withDefault ""
                    |> CookieParser.parse
            )
        |> noErrors
        |> Request


{-| -}
expectCookie : String -> Request String
expectCookie name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "cookies"
        |> OptimizedDecoder.map
            (\value ->
                case value of
                    Just justValue ->
                        ( Ok justValue, [] )

                    Nothing ->
                        ( Err (ValidationError ("Missing cookie " ++ name)), [] )
            )
        |> Request


{-| -}
cookie : String -> Request (Maybe String)
cookie name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.field "cookies"
        |> noErrors
        |> Request


formField_ : String -> Request String
formField_ name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> OptimizedDecoder.map
            (\value ->
                case value of
                    Just justValue ->
                        ( Ok justValue, [] )

                    Nothing ->
                        ( Err (ValidationError ("Missing form field '" ++ name ++ "'")), [] )
            )
        |> Request


optionalFormField_ : String -> Request (Maybe String)
optionalFormField_ name =
    OptimizedDecoder.optionalField name OptimizedDecoder.string
        |> noErrors
        |> Request


{-| -}
type alias File =
    { name : String
    , mimeType : String
    , body : String
    }


fileField_ : String -> Request File
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
                        ( Ok justValue, [] )

                    Nothing ->
                        ( Err (ValidationError ("Missing form field " ++ name)), [] )
            )
        |> Request


{-| -}
expectFormPost :
    ({ field : String -> Request String
     , optionalField : String -> Request (Maybe String)
     }
     -> Request decodedForm
    )
    -> Request decodedForm
expectFormPost toForm =
    map2 Tuple.pair
        (matchesContentType "application/x-www-form-urlencoded")
        (matchesMethod ( Post, [] ))
        |> andThen
            (\( validContentType, validMethod ) ->
                if not ((validContentType |> Maybe.withDefault False) && validMethod) then
                    OptimizedDecoder.succeed
                        ( Err
                            (NotFormPost
                                { method = Just Get
                                , contentType = Just "TODO"
                                }
                            )
                        , []
                        )
                        |> Request

                else
                    toForm { field = formField_, optionalField = optionalFormField_ }
                        |> (\(Request decoder) -> decoder)
                        |> OptimizedDecoder.optionalField "formData"
                        |> OptimizedDecoder.map
                            (\value ->
                                case value of
                                    Just ( decodedForm, errors ) ->
                                        ( decodedForm, errors )

                                    Nothing ->
                                        ( Err (ValidationError "Expected form data"), [] )
                            )
                        |> Request
            )


{-| -}
expectMultiPartFormPost :
    ({ field : String -> Request String
     , optionalField : String -> Request (Maybe String)
     , fileField : String -> Request File
     }
     -> Request decodedForm
    )
    -> Request decodedForm
expectMultiPartFormPost toForm =
    map2 (\_ value -> value)
        (expectContentType "multipart/form-data")
        (toForm
            { field = formField_
            , optionalField = optionalFormField_
            , fileField = fileField_
            }
            |> (\(Request decoder) -> decoder)
            |> OptimizedDecoder.field "multiPartFormData"
            |> Request
            |> acceptMethod ( Post, [] )
        )


{-| -}
body : Request (Maybe String)
body =
    bodyDecoder
        |> noErrors
        |> Request


{-| -}
expectContentType : String -> Request Bool
expectContentType expectedContentType =
    OptimizedDecoder.optionalField ("content-type" |> String.toLower) OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> OptimizedDecoder.map
            (\maybeContentType ->
                case maybeContentType of
                    Nothing ->
                        ( Err (ValidationError "Missing content-type"), [] )

                    Just contentType ->
                        if (contentType |> parseContentType) == (expectedContentType |> parseContentType) then
                            ( Ok True, [] )

                        else
                            ( Ok False, [ ValidationError ("Expected content-type to be " ++ expectedContentType ++ " but it was " ++ contentType) ] )
            )
        |> Request


matchesContentType : String -> Request (Maybe Bool)
matchesContentType expectedContentType =
    OptimizedDecoder.optionalField ("content-type" |> String.toLower) OptimizedDecoder.string
        |> OptimizedDecoder.field "headers"
        |> OptimizedDecoder.map
            (\maybeContentType ->
                case maybeContentType of
                    Nothing ->
                        Nothing

                    Just contentType ->
                        if (contentType |> parseContentType) == (expectedContentType |> parseContentType) then
                            Just True

                        else
                            Just False
            )
        |> noErrors
        |> Request


parseContentType : String -> String
parseContentType rawContentType =
    rawContentType
        |> String.split ";"
        |> List.head
        |> Maybe.withDefault rawContentType


{-| -}
expectJsonBody : OptimizedDecoder.Decoder value -> Request value
expectJsonBody jsonBodyDecoder =
    map2 (\_ secondValue -> secondValue)
        (expectContentType "application/json")
        (OptimizedDecoder.oneOf
            [ OptimizedDecoder.field "jsonBody" jsonBodyDecoder
                |> OptimizedDecoder.map Ok
            , OptimizedDecoder.field "jsonBody" OptimizedDecoder.value
                |> OptimizedDecoder.map (OptimizedDecoder.decodeValue jsonBodyDecoder)
                |> OptimizedDecoder.map (Result.mapError JsonDecodeError)
            ]
            |> OptimizedDecoder.map (\value -> ( value, [] ))
            |> Request
        )


{-| -}
jsonBodyResult : OptimizedDecoder.Decoder value -> Request (Result Json.Decode.Error value)
jsonBodyResult jsonBodyDecoder =
    map2 (\_ secondValue -> secondValue)
        (expectContentType "application/json")
        (OptimizedDecoder.oneOf
            [ OptimizedDecoder.field "jsonBody" jsonBodyDecoder
                |> OptimizedDecoder.map Ok
            , OptimizedDecoder.field "jsonBody" OptimizedDecoder.value
                |> OptimizedDecoder.map (OptimizedDecoder.decodeValue jsonBodyDecoder)
            ]
            |> noErrors
            |> Request
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
