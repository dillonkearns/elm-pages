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
import QueryParams exposing (QueryParams)
import Time


{-| -}
type Request decodesTo
    = Request (Json.Decode.Decoder ( Result ValidationError decodesTo, List ValidationError ))


oneOfInternal : List ValidationError -> List (Json.Decode.Decoder ( Result ValidationError decodesTo, List ValidationError )) -> Json.Decode.Decoder ( Result ValidationError decodesTo, List ValidationError )
oneOfInternal previousErrors optimizedDecoders =
    case optimizedDecoders of
        [] ->
            Json.Decode.succeed ( Err (OneOf previousErrors), [] )

        [ single ] ->
            single
                |> Json.Decode.map
                    (\result ->
                        result
                            |> Tuple.mapFirst (Result.mapError (\error -> OneOf (previousErrors ++ [ error ])))
                    )

        first :: rest ->
            Json.Decode.oneOf
                [ first
                    |> Json.Decode.andThen
                        (\( firstResult, firstErrors ) ->
                            case ( firstResult, firstErrors ) of
                                ( Ok okFirstResult, [] ) ->
                                    Json.Decode.succeed ( Ok okFirstResult, [] )

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
    Request (Json.Decode.succeed ( Ok value, [] ))


{-| TODO internal only
-}
getDecoder : Request (DataSource response) -> Json.Decode.Decoder (Result ( ValidationError, List ValidationError ) (DataSource response))
getDecoder (Request decoder) =
    decoder
        |> Json.Decode.map
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
        (Json.Decode.map
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
    Json.Decode.andThen
        (\value ->
            case value of
                ( Ok okValue, errors ) ->
                    okValue
                        |> toRequestB
                        |> unwrap

                ( Err error, errors ) ->
                    Json.Decode.succeed ( Err error, errors )
        )
        requestA
        |> Request


unwrap : Request a -> Json.Decode.Decoder ( Result ValidationError a, List ValidationError )
unwrap (Request decoder_) =
    decoder_


{-| -}
map2 : (a -> b -> c) -> Request a -> Request b -> Request c
map2 f (Request jdA) (Request jdB) =
    Request
        (Json.Decode.map2
            (\( result1, errors1 ) ( result2, errors2 ) ->
                ( Result.map2 f result1 result2
                , errors1 ++ errors2
                )
            )
            jdA
            jdB
        )


optionalField : String -> Json.Decode.Decoder a -> Json.Decode.Decoder (Maybe a)
optionalField fieldName decoder_ =
    let
        finishDecoding : Json.Decode.Value -> Json.Decode.Decoder (Maybe a)
        finishDecoding json =
            case Json.Decode.decodeValue (Json.Decode.field fieldName Json.Decode.value) json of
                Ok _ ->
                    -- The field is present, so run the decoder on it.
                    Json.Decode.map Just (Json.Decode.field fieldName decoder_)

                Err _ ->
                    -- The field was missing, which is fine!
                    Json.Decode.succeed Nothing
    in
    Json.Decode.value
        |> Json.Decode.andThen finishDecoding


fromResult : Result String value -> Json.Decode.Decoder value
fromResult result =
    case result of
        Ok okValue ->
            Json.Decode.succeed okValue

        Err error ->
            Json.Decode.fail error


{-| -}
expectHeader : String -> Request String
expectHeader headerName =
    optionalField (headerName |> String.toLower) Json.Decode.string
        |> Json.Decode.field "headers"
        |> Json.Decode.andThen (\value -> fromResult (value |> Result.fromMaybe "Missing field headers"))
        |> noErrors
        |> Request


{-| -}
requestTime : Request Time.Posix
requestTime =
    Json.Decode.field "requestTime"
        (Json.Decode.int |> Json.Decode.map Time.millisToPosix)
        |> noErrors
        |> Request


okOrInternalError : Json.Decode.Decoder a -> Json.Decode.Decoder (Result ValidationError a)
okOrInternalError decoder =
    Json.Decode.maybe decoder
        |> Json.Decode.map (Result.fromMaybe InternalError)


{-| -}
method : Request Method
method =
    (Json.Decode.field "method" Json.Decode.string
        |> Json.Decode.map methodFromString
    )
        |> noErrors
        |> Request


noErrors : Json.Decode.Decoder value -> Json.Decode.Decoder ( Result ValidationError value, List ValidationError )
noErrors decoder =
    decoder
        |> Json.Decode.map (\value -> ( Ok value, [] ))


{-| -}
acceptContentTypes : ( String, List String ) -> Request value -> Request value
acceptContentTypes ( accepted1, accepted ) (Request decoder) =
    -- TODO this should parse content-types so it doesn't need to be an exact match (support `; q=...`, etc.)
    optionalField ("Accept" |> String.toLower) Json.Decode.string
        |> Json.Decode.field "headers"
        |> Json.Decode.andThen
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
    (Json.Decode.field "method" Json.Decode.string
        |> Json.Decode.map methodFromString
        |> Json.Decode.andThen
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
    (Json.Decode.field "method" Json.Decode.string
        |> Json.Decode.map methodFromString
        |> Json.Decode.map
            (\method_ ->
                (accepted1 :: accepted) |> List.member method_
            )
    )
        |> noErrors
        |> Request


appendError : ValidationError -> Json.Decode.Decoder ( value, List ValidationError ) -> Json.Decode.Decoder ( value, List ValidationError )
appendError error decoder =
    decoder
        |> Json.Decode.map (Tuple.mapSecond (\errors -> error :: errors))


{-| -}
allQueryParams : Request QueryParams
allQueryParams =
    Json.Decode.field "query" Json.Decode.string
        |> Json.Decode.map QueryParams.fromString
        |> noErrors
        |> Request


{-| -}
queryParam : String -> Request (Maybe String)
queryParam name =
    optionalField name Json.Decode.string
        |> Json.Decode.field "query"
        |> noErrors
        |> Request


{-| -}
expectQueryParam : String -> Request String
expectQueryParam name =
    optionalField name Json.Decode.string
        |> Json.Decode.field "query"
        |> Json.Decode.map
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
    optionalField (headerName |> String.toLower) Json.Decode.string
        |> Json.Decode.field "headers"
        |> noErrors
        |> Request


{-| -}
allCookies : Request (Dict String String)
allCookies =
    optionalField "cookie" Json.Decode.string
        |> Json.Decode.field "headers"
        |> Json.Decode.map
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
    optionalField name Json.Decode.string
        |> Json.Decode.field "cookies"
        |> Json.Decode.map
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
    optionalField name Json.Decode.string
        |> Json.Decode.field "cookies"
        |> noErrors
        |> Request


formField_ : String -> Request String
formField_ name =
    optionalField name Json.Decode.string
        |> Json.Decode.map
            (\value ->
                case value of
                    Just justValue ->
                        ( Ok justValue, [] )

                    Nothing ->
                        ( Err (ValidationError ("Missing form field " ++ name)), [] )
            )
        |> Request


optionalFormField_ : String -> Request (Maybe String)
optionalFormField_ name =
    optionalField name Json.Decode.string
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
    optionalField name
        (Json.Decode.oneOf
            [ Json.Decode.map3 File
                (Json.Decode.field "filename" Json.Decode.string)
                (Json.Decode.field "mimeType" Json.Decode.string)
                (Json.Decode.field "body" Json.Decode.string)
            ]
        )
        |> Json.Decode.map
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
                    Json.Decode.succeed
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
                        |> optionalField "formData"
                        |> Json.Decode.map
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
            |> Json.Decode.field "multiPartFormData"
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
    optionalField ("content-type" |> String.toLower) Json.Decode.string
        |> Json.Decode.field "headers"
        |> Json.Decode.map
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
    optionalField ("content-type" |> String.toLower) Json.Decode.string
        |> Json.Decode.field "headers"
        |> Json.Decode.map
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
expectJsonBody : Json.Decode.Decoder value -> Request value
expectJsonBody jsonBodyDecoder =
    map2 (\_ secondValue -> secondValue)
        (expectContentType "application/json")
        (Json.Decode.oneOf
            [ Json.Decode.field "jsonBody" jsonBodyDecoder
                |> Json.Decode.map Ok
            , Json.Decode.field "jsonBody" Json.Decode.value
                |> Json.Decode.map (Json.Decode.decodeValue jsonBodyDecoder)
                |> Json.Decode.map (Result.mapError JsonDecodeError)
            ]
            |> Json.Decode.map (\value -> ( value, [] ))
            |> Request
        )


{-| -}
jsonBodyResult : Json.Decode.Decoder value -> Request (Result Json.Decode.Error value)
jsonBodyResult jsonBodyDecoder =
    map2 (\_ secondValue -> secondValue)
        (expectContentType "application/json")
        (Json.Decode.oneOf
            [ Json.Decode.field "jsonBody" jsonBodyDecoder
                |> Json.Decode.map Ok
            , Json.Decode.field "jsonBody" Json.Decode.value
                |> Json.Decode.map (Json.Decode.decodeValue jsonBodyDecoder)
            ]
            |> noErrors
            |> Request
        )


bodyDecoder : Json.Decode.Decoder (Maybe String)
bodyDecoder =
    Json.Decode.field "body" (Json.Decode.nullable Json.Decode.string)


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
