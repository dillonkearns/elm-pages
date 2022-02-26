module Server.Request exposing
    ( Request(..)
    , Method(..), methodToString
    , succeed
    , requestTime, optionalHeader, expectContentType, expectJsonBody, jsonBodyResult
    , acceptMethod, acceptContentTypes
    , map, map2, oneOf, andMap, andThen
    , expectQueryParam
    , cookie, expectCookie
    , expectHeader
    , expectFormPost
    , File, expectMultiPartFormPost
    , map3
    , errorsToString, errorToString, getDecoder, ValidationError
    )

{-|

@docs Request

@docs Method, methodToString

@docs succeed

@docs requestTime, optionalHeader, expectContentType, expectJsonBody, jsonBodyResult

@docs acceptMethod, acceptContentTypes


## Transforming

@docs map, map2, oneOf, andMap, andThen


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


## Map Functions

@docs map3


## Internals

@docs errorsToString, errorToString, getDecoder, ValidationError

-}

import DataSource exposing (DataSource)
import Dict
import FormData
import Json.Decode
import Json.Encode
import List.NonEmpty
import Time
import Url


{-| -}
type Request decodesTo
    = Request (Json.Decode.Decoder ( Result ValidationError decodesTo, List ValidationError ))


oneOfInternal : List ValidationError -> List (Json.Decode.Decoder ( Result ValidationError decodesTo, List ValidationError )) -> Json.Decode.Decoder ( Result ValidationError decodesTo, List ValidationError )
oneOfInternal previousErrors optimizedDecoders =
    -- elm-review: known-unoptimized-recursion
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

                                ( Ok _, otherErrors ) ->
                                    oneOfInternal (previousErrors ++ otherErrors) rest

                                ( Err error, _ ) ->
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


{-| -}
type ValidationError
    = ValidationError String
    | OneOf (List ValidationError)
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
    -- elm-review: known-unoptimized-recursion
    case validationError of
        ValidationError message ->
            message

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


{-| -}
andThen : (a -> Request b) -> Request a -> Request b
andThen toRequestB (Request requestA) =
    Json.Decode.andThen
        (\value ->
            case value of
                ( Ok okValue, _ ) ->
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


{-| -}
map3 :
    (value1 -> value2 -> value3 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request valueCombined
map3 combineFn request1 request2 request3 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3


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
                        ( Err (ValidationError ("Missing form field '" ++ name ++ "'")), [] )
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
                    Json.Decode.field "body" Json.Decode.string
                        |> Json.Decode.map FormData.parse
                        |> Json.Decode.andThen
                            (\parsedForm ->
                                let
                                    thing =
                                        parsedForm
                                            |> Dict.toList
                                            |> List.map
                                                (Tuple.mapSecond
                                                    (\( first, rest ) ->
                                                        Json.Encode.string first
                                                    )
                                                )
                                            |> Json.Encode.object
                                in
                                Json.Decode.succeed thing
                            )
                        |> noErrors
                        |> Request
                        |> andThen
                            (\parsedForm ->
                                let
                                    innerDecoder =
                                        toForm { field = formField_, optionalField = optionalFormField_ }
                                            |> (\(Request decoder) -> decoder)
                                in
                                Json.Decode.decodeValue innerDecoder parsedForm
                                    |> Result.mapError Json.Decode.errorToString
                                    |> fromResult
                                    |> Request
                            )
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
    map2
        (\_ value ->
            value
        )
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


expectJsonBody : Json.Decode.Decoder value -> Request value
expectJsonBody jsonBodyDecoder =
    map2 (\_ secondValue -> secondValue)
        (expectContentType "application/json")
        (Json.Decode.oneOf
            [ Json.Decode.field "body" Json.Decode.string
                |> Json.Decode.andThen
                    (\rawBody ->
                        Json.Decode.decodeString jsonBodyDecoder rawBody
                            |> Result.mapError Json.Decode.errorToString
                            |> fromResult
                    )
                |> noErrors
            , Json.Decode.succeed ( Err (ValidationError "Tried to parse JSON body but the request had no body."), [] )
            ]
            |> Request
        )


rawUrl : Request String
rawUrl =
    Json.Decode.field "rawUrl" Json.Decode.string
        |> noErrors
        |> Request


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
