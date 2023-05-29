module Server.Request exposing
    ( Request
    , requestTime
    , header, headers
    , method, Method(..), methodToString
    , body, jsonBody
    , formData, formDataWithServerValidation
    , rawFormData
    , rawUrl
    , queryParam, queryParams
    , matchesContentType
    , cookie, cookies
    )

{-| Server-rendered Route modules and [server-rendered API Routes](ApiRoute#serverRender) give you access to a `Server.Request.Request` argument.

@docs Request

For example, in a server-rendered route,
you could check a session cookie to decide whether to respond by rendering a page
for the logged-in user, or else respond with an HTTP redirect response (see the [`Server.Response` docs](Server-Response)).

You can access the incoming HTTP request's:

  - [Headers](#headers)
  - [Cookies](#cookies)
  - [`method`](#method)
  - [`rawUrl`](#rawUrl)
  - [`requestTime`](#requestTime) (as a `Time.Posix`)

There are also some high-level helpers that take the low-level Request data and let you parse it into Elm types:

  - [`jsonBody`](#jsonBody)
  - [Form Helpers](#forms)
  - [URL query parameters](#queryParam)
  - [Content Type](#content-type)

Note that this data is not available for pre-rendered pages or pre-rendered API Routes, only for server-rendered pages.
This is because when a page is pre-rendered, there _is_ no incoming HTTP request to respond to, it is rendered before a user
requests the page and then the pre-rendered page is served as a plain file (without running your Route Module).

That's why `RouteBuilder.preRender` does not have a `Server.Request.Request` argument.

    import BackendTask exposing (BackendTask)
    import RouteBuilder exposing (StatelessRoute)

    type alias Data =
        {}

    data : RouteParams -> BackendTask Data
    data routeParams =
        BackendTask.succeed Data

    route : StatelessRoute RouteParams Data ActionData
    route =
        RouteBuilder.preRender
            { data = data
            , head = head
            , pages = pages
            }
            |> RouteBuilder.buildNoState { view = view }

A server-rendered Route Module _does_ have access to a user's incoming HTTP request because it runs every time the page
is loaded. That's why `data` has a `Server.Request.Request` argument in server-rendered Route Modules. Since you have an incoming HTTP request for server-rendered routes,
`RouteBuilder.serverRender` has `data : RouteParams -> Request.Parser (BackendTask (Response Data))`. That means that you
can use the incoming HTTP request data to choose how to respond. For example, you could check for a dark-mode preference
cookie and render a light- or dark-themed page and render a different page.

@docs requestTime


## Headers

@docs header, headers


## Method

@docs method, Method, methodToString


## Body

@docs body, jsonBody


## Forms

@docs formData, formDataWithServerValidation

@docs rawFormData


## URL

@docs rawUrl

@docs queryParam, queryParams


## Content Type

@docs matchesContentType


## Cookies

@docs cookie, cookies

-}

import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import FatalError exposing (FatalError)
import Form
import Form.Handler
import Form.Validation as Validation
import FormData
import Internal.Request
import Json.Decode
import List.NonEmpty
import Pages.Form
import QueryParams
import Time
import Url


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


{-| -}
headers : Request -> Dict String String
headers (Internal.Request.Request req) =
    req.rawHeaders


{-| Get the `Time.Posix` when the incoming HTTP request was received.
-}
requestTime : Request -> Time.Posix
requestTime (Internal.Request.Request req) =
    req.time


{-| The [HTTP request method](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods) of the incoming request.

Note that Route modules `data` is run for `GET` requests, and `action` is run for other request methods (including `POST`, `PUT`, `DELETE`).
So you don't need to check the `method` in your Route Module's `data` function, though you can choose to do so in its `action`.

-}
method : Request -> Method
method (Internal.Request.Request req) =
    req.method |> methodFromString


{-| Get `Nothing` if the query param with the given name is missing, or `Just` the value if it is present.

If there are multiple query params with the same name, the first one is returned.

    queryParam "coupon"

    -- url: http://example.com?coupon=abc
    -- parses into: Just "abc"

    queryParam "coupon"

    -- url: http://example.com?coupon=abc&coupon=xyz
    -- parses into: Just "abc"

    queryParam "coupon"

    -- url: http://example.com
    -- parses into: Nothing

See also [`queryParams`](#queryParams), or [`rawUrl`](#rawUrl) if you need something more low-level.

-}
queryParam : String -> Request -> Maybe String
queryParam name (Internal.Request.Request req) =
    req.rawUrl
        |> Url.fromString
        |> Maybe.andThen .query
        |> Maybe.andThen (findFirstQueryParam name)


findFirstQueryParam : String -> String -> Maybe String
findFirstQueryParam name queryString =
    queryString
        |> QueryParams.fromString
        |> Dict.get name
        |> Maybe.andThen List.head


{-| Gives all query params from the URL.

    queryParam "coupon"

    -- url: http://example.com?coupon=abc
    -- parses into: Dict.fromList [("coupon", ["abc"])]

    queryParam "coupon"

    -- url: http://example.com?coupon=abc&coupon=xyz
    -- parses into: Dict.fromList [("coupon", ["abc", "xyz"])]

-}
queryParams : Request -> Dict String (List String)
queryParams (Internal.Request.Request req) =
    req.rawUrl
        |> Url.fromString
        |> Maybe.andThen .query
        |> Maybe.map QueryParams.fromString
        |> Maybe.withDefault Dict.empty


{-| The full URL of the incoming HTTP request, including the query params.

Note that the fragment is not included because this is client-only (not sent to the server).

    rawUrl request

    -- url: http://example.com?coupon=abc
    -- parses into: "http://example.com?coupon=abc"

    rawUrl request

    -- url: https://example.com?coupon=abc&coupon=xyz
    -- parses into: "https://example.com?coupon=abc&coupon=xyz"

-}
rawUrl : Request -> String
rawUrl (Internal.Request.Request req) =
    req.rawUrl


{-| Get a header from the request. The header name is case-insensitive.

Header: Accept-Language: en-US,en;q=0.5

    request |> Request.header "Accept-Language"
    -- Just "Accept-Language: en-US,en;q=0.5"

-}
header : String -> Request -> Maybe String
header headerName (Internal.Request.Request req) =
    req.rawHeaders
        |> Dict.get (headerName |> String.toLower)


{-| Get a cookie from the request. For a more high-level API, see [`Server.Session`](Server-Session).
-}
cookie : String -> Request -> Maybe String
cookie name (Internal.Request.Request req) =
    req.cookies
        |> Dict.get name


{-| Get all of the cookies from the incoming HTTP request. For a more high-level API, see [`Server.Session`](Server-Session).
-}
cookies : Request -> Dict String String
cookies (Internal.Request.Request req) =
    req.cookies



--formField_ : String -> Parser String
--formField_ name =
--    optionalField name Json.Decode.string
--        |> Json.Decode.map
--            (\value ->
--                case value of
--                    Just justValue ->
--                        ( Ok justValue, [] )
--
--                    Nothing ->
--                        ( Err (ValidationError ("Missing form field '" ++ name ++ "'")), [] )
--            )
--        |> Internal.Request.Parser
--
--
--optionalFormField_ : String -> Parser (Maybe String)
--optionalFormField_ name =
--    optionalField name Json.Decode.string
--        |> noErrors
--        |> Internal.Request.Parser
--{-| -}
--type alias File =
--    { name : String
--    , mimeType : String
--    , body : String
--    }
--fileField_ : String -> Parser File
--fileField_ name =
--    optionalField name
--        (Json.Decode.map3 File
--            (Json.Decode.field "filename" Json.Decode.string)
--            (Json.Decode.field "mimeType" Json.Decode.string)
--            (Json.Decode.field "body" Json.Decode.string)
--        )
--        |> Json.Decode.map
--            (\value ->
--                case value of
--                    Just justValue ->
--                        ( Ok justValue, [] )
--
--                    Nothing ->
--                        ( Err (ValidationError ("Missing form field " ++ name)), [] )
--            )
--        |> Internal.Request.Parser


runForm : Validation.Validation error parsed kind constraints -> Form.Validated error parsed
runForm validation =
    Form.Handler.run []
        (Form.Handler.init identity
            (Form.form
                { combine = validation
                , view = []
                }
            )
        )


{-| -}
formDataWithServerValidation :
    Pages.Form.Handler error combined
    -> Request
    -> Maybe (BackendTask FatalError (Result (Form.ServerResponse error) ( Form.ServerResponse error, combined )))
formDataWithServerValidation formParsers (Internal.Request.Request req) =
    case req.body of
        Nothing ->
            Nothing

        Just body_ ->
            FormData.parseToList body_
                |> (\rawFormData_ ->
                        case Form.Handler.run rawFormData_ formParsers of
                            Form.Valid decoded ->
                                decoded
                                    |> BackendTask.map
                                        (\clientValidated ->
                                            case runForm clientValidated of
                                                Form.Valid decodedFinal ->
                                                    Ok
                                                        ( { persisted =
                                                                { fields = Just rawFormData_
                                                                , clientSideErrors = Nothing
                                                                }
                                                          , serverSideErrors = Dict.empty
                                                          }
                                                        , decodedFinal
                                                        )

                                                Form.Invalid _ errors2 ->
                                                    Err
                                                        { persisted =
                                                            { fields = Just rawFormData_
                                                            , clientSideErrors = Just errors2
                                                            }
                                                        , serverSideErrors = Dict.empty
                                                        }
                                        )

                            Form.Invalid _ errors ->
                                Err
                                    { persisted =
                                        { fields = Just rawFormData_
                                        , clientSideErrors = Just errors
                                        }
                                    , serverSideErrors = Dict.empty
                                    }
                                    |> BackendTask.succeed
                   )
                |> Just


{-| Takes a [`Form.Handler.Handler`](https://package.elm-lang.org/packages/dillonkearns/elm-form/latest/Form-Handler) and
parses the raw form data into a [`Form.Validated`](https://package.elm-lang.org/packages/dillonkearns/elm-form/latest/Form#Validated) value.

This is the standard pattern for dealing with form data in `elm-pages`. You can share your code for your [`Form`](https://package.elm-lang.org/packages/dillonkearns/elm-form/latest/Form#Form)
definitions between your client and server code, using this function to parse the raw form data into a `Form.Validated` value for the backend,
and [`Pages.Form`](Pages-Form) to render the `Form` on the client.

Since we are sharing the `Form` definition between frontend and backend, we get to re-use the same validation logic so we gain confidence that
the validation errors that the user sees on the client are protected on our backend, and vice versa.

    import BackendTask
    import Form
    import Server.Request

    type Action
        = Delete
        | CreateOrUpdate Post

    formHandlers : Form.Handler.Handler String Action
    formHandlers =
        deleteForm
            |> Form.Handler.init (\() -> Delete)
            |> Form.Handler.with CreateOrUpdate createOrUpdateForm

    deleteForm : Form.HtmlForm String () input msg

    createOrUpdateForm : Form.HtmlForm String Post Post msg

    action :
        RouteParams
        -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
    action routeParams =
        Server.Request.map
            (\( formResponse, parsedForm ) ->
                case parsedForm of
                    Form.Valid Delete ->
                        deletePostBySlug routeParams.slug
                            |> BackendTask.map
                                (\() -> Route.redirectTo Route.Index)

                    Form.Valid (CreateOrUpdate post) ->
                        let
                            createPost : Bool
                            createPost =
                                okForm.slug == "new"
                        in
                        createOrUpdatePost post
                            |> BackendTask.map
                                (\() ->
                                    Route.redirectTo
                                        (Route.Admin__Slug_ { slug = okForm.slug })
                                )

                    Form.Invalid _ invalidForm ->
                        BackendTask.succeed
                            (Server.Response.render
                                { errors = formResponse }
                            )
            )
            (Server.Request.formData formHandlers)

You can handle form submissions as either GET or POST requests. Note that for security reasons, it's important to performing mutations with care from GET requests,
since a GET request can be performed from an outside origin by embedding an image that points to the given URL. So a logout submission should be protected by
using `POST` to ensure that you can't log users out by embedding an image with a logout URL in it.

If the request has HTTP method `GET`, the form data will come from the query parameters.

If the request has the HTTP method `POST` _and_ the `Content-Type` is `application/x-www-form-urlencoded`, it will return the
decoded form data from the body of the request.

Otherwise, this `Parser` will not match.

Note that in server-rendered Route modules, your `data` function will handle `GET` requests (and will _not_ receive any `POST` requests),
while your `action` will receive POST (and other non-GET) requests.

By default, [`Form`]'s are rendered with a `POST` method, and you can configure them to submit `GET` requests using [`withGetMethod`](https://package.elm-lang.org/packages/dillonkearns/elm-form/latest/Form#withGetMethod).
So you will want to handle any `Form`'s rendered using `withGetMethod` in your Route's `data` function, or otherwise handle forms in `action`.

-}
formData :
    Form.Handler.Handler error combined
    -> Request
    -> Maybe ( Form.ServerResponse error, Form.Validated error combined )
formData formParsers ((Internal.Request.Request req) as request) =
    request
        |> rawFormData
        |> Maybe.map
            (\rawFormData_ ->
                case Form.Handler.run rawFormData_ formParsers of
                    (Form.Valid _) as validated ->
                        ( { persisted =
                                { fields = Just rawFormData_
                                , clientSideErrors = Just Dict.empty
                                }
                          , serverSideErrors = Dict.empty
                          }
                        , validated
                        )

                    (Form.Invalid _ maybeErrors) as validated ->
                        ( { persisted =
                                { fields = Just rawFormData_
                                , clientSideErrors = Just maybeErrors
                                }
                          , serverSideErrors = Dict.empty
                          }
                        , validated
                        )
            )


{-| Get the raw key-value pairs from a form submission.

If the request has the HTTP method `GET`, it will return the query parameters.

If the request has the HTTP method `POST` _and_ the `Content-Type` is `application/x-www-form-urlencoded`, it will return the
decoded form data from the body of the request.

Otherwise, this `Parser` will not match.

Note that in server-rendered Route modules, your `data` function will handle `GET` requests (and will _not_ receive any `POST` requests),
while your `action` will receive POST (and other non-GET) requests.

By default, [`Form`]'s are rendered with a `POST` method, and you can configure them to submit `GET` requests using [`withGetMethod`](https://package.elm-lang.org/packages/dillonkearns/elm-form/latest/Form#withGetMethod).
So you will want to handle any `Form`'s rendered using `withGetMethod` in your Route's `data` function, or otherwise handle forms in `action`.

-}
rawFormData : Request -> Maybe (List ( String, String ))
rawFormData request =
    if method request == Get then
        request
            |> queryParams
            |> Dict.toList
            |> List.map (Tuple.mapSecond (List.head >> Maybe.withDefault ""))
            |> Just

    else if (method request == Post) && (request |> matchesContentType "application/x-www-form-urlencoded") then
        body request
            |> Maybe.map
                (\justBody ->
                    justBody
                        |> FormData.parseToList
                )

    else
        Nothing



--{-| -}
--expectMultiPartFormPost :
--    ({ field : String -> Parser String
--     , optionalField : String -> Parser (Maybe String)
--     , fileField : String -> Parser File
--     }
--     -> Parser decodedForm
--    )
--    -> Parser decodedForm
--expectMultiPartFormPost toForm =
--    map2
--        (\_ value ->
--            value
--        )
--        (expectContentType "multipart/form-data")
--        (toForm
--            { field = formField_
--            , optionalField = optionalFormField_
--            , fileField = fileField_
--            }
--            |> (\(Internal.Request.Parser decoder) -> decoder)
--            -- @@@ TODO is it possible to do multipart form data parsing in pure Elm?
--            |> Json.Decode.field "multiPartFormData"
--            |> Internal.Request.Parser
--            |> acceptMethod ( Post, [] )
--        )


rawContentType : Request -> Maybe String
rawContentType (Internal.Request.Request req) =
    req.rawHeaders |> Dict.get "content-type"


{-| True if the `content-type` header is present AND matches the given argument.

Examples:

    Content-Type: application/json; charset=utf-8
    request |> matchesContentType "application/json"
    -- True

    Content-Type: application/json
    request |> matchesContentType "application/json"
    -- True

    Content-Type: application/json
    request |> matchesContentType "application/xml"
    -- False

-}
matchesContentType : String -> Request -> Bool
matchesContentType expectedContentType (Internal.Request.Request req) =
    req.rawHeaders
        |> Dict.get "content-type"
        |> (\maybeContentType ->
                case maybeContentType of
                    Nothing ->
                        False

                    Just contentType ->
                        (contentType |> parseContentType) == (expectedContentType |> parseContentType)
           )


parseContentType : String -> String
parseContentType contentTypeString =
    contentTypeString
        |> String.split ";"
        |> List.head
        |> Maybe.map String.trim
        |> Maybe.withDefault contentTypeString


{-| If the request has a body and its `Content-Type` matches JSON, then
try running a JSON decoder on the body of the request. Otherwise, return `Nothing`.

Example:

    Body: { "name": "John" }
    Headers:
    Content-Type: application/json
    request |> jsonBody (Json.Decode.field "name" Json.Decode.string)
    -- Just (Ok "John")

    Body: { "name": "John" }
    No Headers
    jsonBody (Json.Decode.field "name" Json.Decode.string) request
    -- Nothing

    No Body
    No Headers
    jsonBody (Json.Decode.field "name" Json.Decode.string) request
    -- Nothing

-}
jsonBody : Json.Decode.Decoder value -> Request -> Maybe (Result Json.Decode.Error value)
jsonBody jsonBodyDecoder ((Internal.Request.Request req) as request) =
    case ( req.body, request |> matchesContentType "application/json" ) of
        ( Just body_, True ) ->
            Json.Decode.decodeString jsonBodyDecoder body_
                |> Just

        _ ->
            Nothing


{-| An [Incoming HTTP Request Method](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods).
-}
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


{-| Gets the HTTP Method as an uppercase String.

Examples:

    Get
        |> methodToString
        -- "GET"

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


{-| A value that lets you access data from the incoming HTTP request.
-}
type alias Request =
    Internal.Request.Request


{-| The Request body, if present (or `Nothing` if there is no request body).
-}
body : Request -> Maybe String
body (Internal.Request.Request req) =
    req.body
