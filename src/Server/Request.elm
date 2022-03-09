module Server.Request exposing
    ( Parser
    , method, rawBody, allCookies, rawHeaders, queryParams
    , Method(..), methodToString
    , succeed, fromResult, skip, validationError
    , requestTime, optionalHeader, expectContentType, expectJsonBody
    , acceptMethod, acceptContentTypes
    , map, map2, oneOf, andMap, andThen
    , expectQueryParam
    , cookie, expectCookie
    , expectHeader
    , File, expectMultiPartFormPost
    , expectBody
    , expectFormPost
    , map3, map4, map5, map6, map7, map8, map9
    , errorsToString, errorToString, getDecoder, ValidationError
    )

{-|

@docs Parser


## Direct Values

@docs method, rawBody, allCookies, rawHeaders, queryParams

@docs Method, methodToString

@docs succeed, fromResult, skip, validationError

@docs requestTime, optionalHeader, expectContentType, expectJsonBody

@docs acceptMethod, acceptContentTypes


## Transforming

@docs map, map2, oneOf, andMap, andThen


## Query Parameters

@docs expectQueryParam


## Cookies

@docs cookie, expectCookie


## Headers

@docs expectHeader


## Multi-part forms and file uploads

@docs File, expectMultiPartFormPost


## Request Parsers That Can Fail

@docs expectBody
@docs expectFormPost


## Map Functions

@docs map3, map4, map5, map6, map7, map8, map9


## Internals

@docs errorsToString, errorToString, getDecoder, ValidationError

-}

import CookieParser
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import FormData
import Json.Decode
import Json.Encode
import List.NonEmpty
import QueryParams
import Time
import Url


{-| A `Server.Request.Parser` lets you send a `Server.Response.Response` based on an incoming HTTP request. For example,
using a `Server.Request.Parser`, you could check a session cookie to decide whether to respond by rendering a page
for the logged-in user, or else respond with an HTTP redirect response (see the [`Server.Response` docs](Server-Response)).

You can access the incoming HTTP request's:

  - Headers
  - Cookies
  - [`method`](#method)
  - URL query parameters
  - [`requestTime`](#requestTime) (as a `Time.Posix`)

Note that this data is not available for pre-rendered pages or pre-rendered API Routes, only for server-rendered pages.
This is because when a page is pre-rendered, there _is_ no incoming HTTP request to respond to, it is rendered before a user
requests the page and then the pre-rendered page is served as a plain file (without running your Route Module).

That's why `RouteBuilder.preRender` has `data : RouteParams -> DataSource Data`:

    import DataSource exposing (DataSource)
    import RouteBuilder exposing (StatelessRoute)

    type alias Data =
        {}

    data : RouteParams -> DataSource Data
    data routeParams =
        DataSource.succeed Data

    route : StatelessRoute RouteParams Data
    route =
        RouteBuilder.preRender
            { data = data
            , head = head
            , pages = pages
            }
            |> RouteBuilder.buildNoState { view = view }

A server-rendered Route Module _does_ have access to a user's incoming HTTP request because it runs every time the page
is loaded. That's why `data` is a `Request.Parser` in server-rendered Route Modules. Since you have an incoming HTTP request for server-rendered routes,
`RouteBuilder.serverRender` has `data : RouteParams -> Request.Parser (DataSource (Response Data))`. That means that you
can use the incoming HTTP request data to choose how to respond. For example, you could check for a dark-mode preference
cookie and render a light- or dark-themed page and render a different page.

That's a mouthful, so let's unpack what it means.

`Request.Parser` means you can pull out

data from the request payload using a Server Request Parser.

    import DataSource exposing (DataSource)
    import RouteBuilder exposing (StatelessRoute)
    import Server.Request as Request exposing (Request)
    import Server.Response as Response exposing (Response)

    type alias Data =
        {}

    data :
        RouteParams
        -> Request.Parser (DataSource (Response Data))
    data routeParams =
        {}
            |> Server.Response.render
            |> DataSource.succeed
            |> Request.succeed

    route : StatelessRoute RouteParams Data
    route =
        RouteBuilder.serverRender
            { head = head
            , data = data
            }
            |> RouteBuilder.buildNoState { view = view }

-}
type Parser decodesTo
    = Parser (Json.Decode.Decoder ( Result ValidationError decodesTo, List ValidationError ))


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
succeed : value -> Parser value
succeed value =
    Parser (Json.Decode.succeed ( Ok value, [] ))


{-| TODO internal only
-}
getDecoder : Parser (DataSource response) -> Json.Decode.Decoder (Result ( ValidationError, List ValidationError ) (DataSource response))
getDecoder (Parser decoder) =
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
    | NotFormPost { method : Maybe Method, contentType : Maybe String }
    | MissingQueryParam { missingParam : String, allQueryParams : String }


{-| -}
validationError : String -> ValidationError
validationError =
    ValidationError


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
errorToString validationError_ =
    -- elm-review: known-unoptimized-recursion
    case validationError_ of
        ValidationError message ->
            message

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

        MissingQueryParam record ->
            "Missing query param \"" ++ record.missingParam ++ "\". Query string was `" ++ record.allQueryParams ++ "`"


{-| -}
map : (a -> b) -> Parser a -> Parser b
map mapFn (Parser decoder) =
    Parser
        (Json.Decode.map
            (\( result, errors ) ->
                ( Result.map mapFn result, errors )
            )
            decoder
        )


{-| -}
oneOf : List (Parser a) -> Parser a
oneOf serverRequests =
    Parser
        (oneOfInternal []
            (List.map
                (\(Parser decoder) -> decoder)
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
andMap : Parser a -> Parser (a -> b) -> Parser b
andMap =
    map2 (|>)


{-| -}
andThen : (a -> Parser b) -> Parser a -> Parser b
andThen toRequestB (Parser requestA) =
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
        |> Parser


unwrap : Parser a -> Json.Decode.Decoder ( Result ValidationError a, List ValidationError )
unwrap (Parser decoder_) =
    decoder_


{-| -}
map2 : (a -> b -> c) -> Parser a -> Parser b -> Parser c
map2 f (Parser jdA) (Parser jdB) =
    Parser
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
    -> Parser value1
    -> Parser value2
    -> Parser value3
    -> Parser valueCombined
map3 combineFn request1 request2 request3 =
    succeed combineFn
        |> andMap request1
        |> andMap request2
        |> andMap request3


{-| -}
map4 :
    (value1 -> value2 -> value3 -> value4 -> valueCombined)
    -> Parser value1
    -> Parser value2
    -> Parser value3
    -> Parser value4
    -> Parser valueCombined
map4 combineFn request1 request2 request3 request4 =
    succeed combineFn
        |> andMap request1
        |> andMap request2
        |> andMap request3
        |> andMap request4


{-| -}
map5 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> valueCombined)
    -> Parser value1
    -> Parser value2
    -> Parser value3
    -> Parser value4
    -> Parser value5
    -> Parser valueCombined
map5 combineFn request1 request2 request3 request4 request5 =
    succeed combineFn
        |> andMap request1
        |> andMap request2
        |> andMap request3
        |> andMap request4
        |> andMap request5


{-| -}
map6 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> valueCombined)
    -> Parser value1
    -> Parser value2
    -> Parser value3
    -> Parser value4
    -> Parser value5
    -> Parser value6
    -> Parser valueCombined
map6 combineFn request1 request2 request3 request4 request5 request6 =
    succeed combineFn
        |> andMap request1
        |> andMap request2
        |> andMap request3
        |> andMap request4
        |> andMap request5
        |> andMap request6


{-| -}
map7 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> valueCombined)
    -> Parser value1
    -> Parser value2
    -> Parser value3
    -> Parser value4
    -> Parser value5
    -> Parser value6
    -> Parser value7
    -> Parser valueCombined
map7 combineFn request1 request2 request3 request4 request5 request6 request7 =
    succeed combineFn
        |> andMap request1
        |> andMap request2
        |> andMap request3
        |> andMap request4
        |> andMap request5
        |> andMap request6
        |> andMap request7


{-| -}
map8 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> value8 -> valueCombined)
    -> Parser value1
    -> Parser value2
    -> Parser value3
    -> Parser value4
    -> Parser value5
    -> Parser value6
    -> Parser value7
    -> Parser value8
    -> Parser valueCombined
map8 combineFn request1 request2 request3 request4 request5 request6 request7 request8 =
    succeed combineFn
        |> andMap request1
        |> andMap request2
        |> andMap request3
        |> andMap request4
        |> andMap request5
        |> andMap request6
        |> andMap request7
        |> andMap request8


{-| -}
map9 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> value8 -> value9 -> valueCombined)
    -> Parser value1
    -> Parser value2
    -> Parser value3
    -> Parser value4
    -> Parser value5
    -> Parser value6
    -> Parser value7
    -> Parser value8
    -> Parser value9
    -> Parser valueCombined
map9 combineFn request1 request2 request3 request4 request5 request6 request7 request8 request9 =
    succeed combineFn
        |> andMap request1
        |> andMap request2
        |> andMap request3
        |> andMap request4
        |> andMap request5
        |> andMap request6
        |> andMap request7
        |> andMap request8
        |> andMap request9


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


{-| Turn a Result into a Request. Useful with `andThen`. Turns `Err` into a skipped request handler (non-matching request),
and `Ok` values into a `succeed` (matching request).
-}
fromResult : Result String value -> Parser value
fromResult result =
    case result of
        Ok okValue ->
            succeed okValue

        Err error ->
            skip (ValidationError error)


jsonFromResult : Result String value -> Json.Decode.Decoder value
jsonFromResult result =
    case result of
        Ok okValue ->
            Json.Decode.succeed okValue

        Err error ->
            Json.Decode.fail error


{-| -}
expectHeader : String -> Parser String
expectHeader headerName =
    optionalField (headerName |> String.toLower) Json.Decode.string
        |> Json.Decode.field "headers"
        |> noErrors
        |> Parser
        |> andThen
            (\value ->
                fromResult
                    (value |> Result.fromMaybe "Missing field headers")
            )


{-| -}
rawHeaders : Parser (Dict String String)
rawHeaders =
    Json.Decode.field "headers" (Json.Decode.dict Json.Decode.string)
        |> noErrors
        |> Parser


{-| -}
requestTime : Parser Time.Posix
requestTime =
    Json.Decode.field "requestTime"
        (Json.Decode.int |> Json.Decode.map Time.millisToPosix)
        |> noErrors
        |> Parser


noErrors : Json.Decode.Decoder value -> Json.Decode.Decoder ( Result ValidationError value, List ValidationError )
noErrors decoder =
    decoder
        |> Json.Decode.map (\value -> ( Ok value, [] ))


{-| -}
acceptContentTypes : ( String, List String ) -> Parser value -> Parser value
acceptContentTypes ( accepted1, accepted ) (Parser decoder) =
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
        |> Parser


{-| -}
acceptMethod : ( Method, List Method ) -> Parser value -> Parser value
acceptMethod ( accepted1, accepted ) (Parser decoder) =
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
        |> Parser


{-| -}
method : Parser Method
method =
    Json.Decode.field "method" Json.Decode.string
        |> Json.Decode.map methodFromString
        |> noErrors
        |> Parser


{-| -}
matchesMethod : ( Method, List Method ) -> Parser Bool
matchesMethod ( accepted1, accepted ) =
    (Json.Decode.field "method" Json.Decode.string
        |> Json.Decode.map methodFromString
        |> Json.Decode.map
            (\method_ ->
                (accepted1 :: accepted) |> List.member method_
            )
    )
        |> noErrors
        |> Parser


appendError : ValidationError -> Json.Decode.Decoder ( value, List ValidationError ) -> Json.Decode.Decoder ( value, List ValidationError )
appendError error decoder =
    decoder
        |> Json.Decode.map (Tuple.mapSecond (\errors -> error :: errors))


{-| -}
expectQueryParam : String -> Parser String
expectQueryParam name =
    rawUrl
        |> andThen
            (\url_ ->
                case url_ |> Url.fromString |> Maybe.andThen .query of
                    Just queryString ->
                        let
                            maybeParamValue : Maybe String
                            maybeParamValue =
                                queryString
                                    |> QueryParams.fromString
                                    |> QueryParams.toDict
                                    |> Dict.get name
                                    |> Maybe.andThen List.head
                        in
                        case maybeParamValue of
                            Just okParamValue ->
                                succeed okParamValue

                            Nothing ->
                                --skipMatch (ValidationError ("Missing query param \"" ++ name ++ "\""))
                                skip
                                    (MissingQueryParam
                                        { missingParam = name
                                        , allQueryParams = queryString
                                        }
                                    )

                    Nothing ->
                        skip (ValidationError ("Expected query param \"" ++ name ++ "\", but there were no query params."))
            )


{-| -}
queryParams : Parser (Dict String (List String))
queryParams =
    rawUrl
        |> map
            (\rawUrl_ ->
                rawUrl_
                    |> Url.fromString
                    |> Maybe.andThen .query
                    |> Maybe.map QueryParams.fromString
                    |> Maybe.map QueryParams.toDict
                    |> Maybe.withDefault Dict.empty
            )


{-| -}
skip : ValidationError -> Parser value
skip validationError_ =
    Parser
        (Json.Decode.succeed
            ( Err validationError_, [] )
        )


{-| -}
rawUrl : Parser String
rawUrl =
    Json.Decode.maybe
        (Json.Decode.string
            |> Json.Decode.field "rawUrl"
        )
        |> Json.Decode.map
            (\url_ ->
                case url_ of
                    Just justValue ->
                        ( Ok justValue, [] )

                    Nothing ->
                        ( Err (ValidationError "Internal error - expected rawUrl field but the adapter script didn't provide one."), [] )
            )
        |> Parser


{-| -}
optionalHeader : String -> Parser (Maybe String)
optionalHeader headerName =
    optionalField (headerName |> String.toLower) Json.Decode.string
        |> Json.Decode.field "headers"
        |> noErrors
        |> Parser


{-| -}
expectCookie : String -> Parser String
expectCookie name =
    cookie name
        |> andThen
            (\maybeCookie ->
                case maybeCookie of
                    Just justValue ->
                        succeed justValue

                    Nothing ->
                        skip (ValidationError ("Missing cookie " ++ name))
            )


{-| -}
cookie : String -> Parser (Maybe String)
cookie name =
    allCookies
        |> map (Dict.get name)


{-| -}
allCookies : Parser (Dict String String)
allCookies =
    Json.Decode.field "headers"
        (optionalField "cookie"
            Json.Decode.string
            |> Json.Decode.map (Maybe.map CookieParser.parse)
        )
        |> Json.Decode.map (Maybe.withDefault Dict.empty)
        |> noErrors
        |> Parser


formField_ : String -> Parser String
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
        |> Parser


optionalFormField_ : String -> Parser (Maybe String)
optionalFormField_ name =
    optionalField name Json.Decode.string
        |> noErrors
        |> Parser


{-| -}
type alias File =
    { name : String
    , mimeType : String
    , body : String
    }


fileField_ : String -> Parser File
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
        |> Parser


{-| -}
expectFormPost :
    ({ field : String -> Parser String
     , optionalField : String -> Parser (Maybe String)
     }
     -> Parser decodedForm
    )
    -> Parser decodedForm
expectFormPost toForm =
    map3 (\a b c -> ( a, b, c ))
        (matchesContentType "application/x-www-form-urlencoded")
        (matchesMethod ( Post, [] ))
        (rawBody
            |> andThen (\maybeBody -> maybeBody |> Result.fromMaybe "Not a form POST because there is no body." |> fromResult)
        )
        |> andThen
            (\( validContentType, validMethod, justBody ) ->
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
                        |> Parser

                else
                    justBody
                        |> FormData.parse
                        |> succeed
                        |> andThen
                            (\parsedForm ->
                                let
                                    thing : Json.Encode.Value
                                    thing =
                                        parsedForm
                                            |> Dict.toList
                                            |> List.map
                                                (Tuple.mapSecond
                                                    (\( first, _ ) ->
                                                        Json.Encode.string first
                                                    )
                                                )
                                            |> Json.Encode.object

                                    innerDecoder : Json.Decode.Decoder ( Result ValidationError decodedForm, List ValidationError )
                                    innerDecoder =
                                        toForm { field = formField_, optionalField = optionalFormField_ }
                                            |> (\(Parser decoder) -> decoder)
                                in
                                Json.Decode.decodeValue innerDecoder thing
                                    |> Result.mapError Json.Decode.errorToString
                                    |> jsonFromResult
                                    |> Parser
                            )
            )


{-| -}
expectMultiPartFormPost :
    ({ field : String -> Parser String
     , optionalField : String -> Parser (Maybe String)
     , fileField : String -> Parser File
     }
     -> Parser decodedForm
    )
    -> Parser decodedForm
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
            |> (\(Parser decoder) -> decoder)
            -- @@@ TODO is it possible to do multipart form data parsing in pure Elm?
            |> Json.Decode.field "multiPartFormData"
            |> Parser
            |> acceptMethod ( Post, [] )
        )


{-| -}
expectContentType : String -> Parser Bool
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
        |> Parser


matchesContentType : String -> Parser (Maybe Bool)
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
        |> Parser


parseContentType : String -> String
parseContentType rawContentType =
    rawContentType
        |> String.split ";"
        |> List.head
        |> Maybe.withDefault rawContentType


{-| -}
expectJsonBody : Json.Decode.Decoder value -> Parser value
expectJsonBody jsonBodyDecoder =
    map2 (\_ secondValue -> secondValue)
        (expectContentType "application/json")
        (rawBody
            |> andThen
                (\rawBody_ ->
                    (case rawBody_ of
                        Just body_ ->
                            Json.Decode.decodeString
                                jsonBodyDecoder
                                body_
                                |> Result.mapError Json.Decode.errorToString

                        Nothing ->
                            Err "Tried to parse JSON body but the request had no body."
                    )
                        |> fromResult
                )
        )


{-| -}
rawBody : Parser (Maybe String)
rawBody =
    Json.Decode.field "body" (Json.Decode.nullable Json.Decode.string)
        |> noErrors
        |> Parser


{-| Same as [`rawBody`](#rawBody), but will only match when a body is present in the HTTP request.
-}
expectBody : Parser String
expectBody =
    rawBody
        |> andThen
            (Result.fromMaybe "Expected body but none was present."
                >> fromResult
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
