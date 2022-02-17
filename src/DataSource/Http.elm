module DataSource.Http exposing
    ( RequestDetails
    , get, request
    , Expect, expectString, expectJson
    , expectResponse
    , Body, emptyBody, stringBody, jsonBody
    , Error(..), Metadata, Response(..), expectBytes, expectBytesResponse, expectStringResponse, expectWhatever, internalRequest
    )

{-| `DataSource.Http` requests are an alternative to doing Elm HTTP requests the traditional way using the `elm/http` package.

The key differences are:

  - `DataSource.Http.Request`s are performed once at build time (`Http.Request`s are performed at runtime, at whenever point you perform them)
  - `DataSource.Http.Request`s have a built-in `DataSource.andThen` that allows you to perform follow-up requests without using tasks


## Scenarios where DataSource.Http is a good fit

If you need data that is refreshed often you may want to do a traditional HTTP request with the `elm/http` package.
The kinds of situations that are served well by static HTTP are with data that updates moderately frequently or infrequently (or never).
A common pattern is to trigger a new build when data changes. Many JAMstack services
allow you to send a WebHook to your host (for example, Netlify is a good static file host that supports triggering builds with webhooks). So
you may want to have your site rebuild everytime your calendar feed has an event added, or whenever a page or article is added
or updated on a CMS service like Contentful.

In scenarios like this, you can serve data that is just as up-to-date as it would be using `elm/http`, but you get the performance
gains of using `DataSource.Http.Request`s as well as the simplicity and robustness that comes with it. Read more about these benefits
in [this article introducing DataSource.Http requests and some concepts around it](https://elm-pages.com/blog/static-http).


## Scenarios where DataSource.Http is not a good fit

  - Data that is specific to the logged-in user
  - Data that needs to be the very latest and changes often (for example, sports scores)

@docs RequestDetails
@docs get, request


## Decoding Request Body

@docs Expect, expectString, expectJson


## Expecting Responses

@docs expectResponse


## Building a DataSource.Http Request Body

The way you build a body is analogous to the `elm/http` package. Currently, only `emptyBody` and
`stringBody` are supported. If you have a use case that calls for a different body type, please open a Github issue
and describe your use case!

@docs Body, emptyBody, stringBody, jsonBody

-}

import Bytes exposing (Bytes)
import Bytes.Decode
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Json.Decode
import Json.Encode as Encode
import Pages.Internal.StaticHttpBody as Body
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (RawRequest(..))
import RequestsAndPending


{-| Build an empty body for a DataSource.Http request. See [elm/http's `Http.emptyBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#emptyBody).
-}
emptyBody : Body
emptyBody =
    Body.EmptyBody


{-| Builds a string body for a DataSource.Http request. See [elm/http's `Http.stringBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#stringBody).

Note from the `elm/http` docs:

> The first argument is a [MIME type](https://en.wikipedia.org/wiki/Media_type) of the body. Some servers are strict about this!

-}
stringBody : String -> String -> Body
stringBody contentType content =
    Body.StringBody contentType content


{-| Builds a JSON body for a DataSource.Http request. See [elm/http's `Http.jsonBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#jsonBody).
-}
jsonBody : Encode.Value -> Body
jsonBody content =
    Body.JsonBody content


{-| A body for a DataSource.Http request.
-}
type alias Body =
    Body.Body


{-| A simplified helper around [`DataSource.Http.request`](#request), which builds up a DataSource.Http GET request.

    import DataSource
    import DataSource.Http
    import Json.Decode as Decode exposing (Decoder)

    getRequest : DataSource Int
    getRequest =
        DataSource.Http.get
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.field "stargazers_count" Decode.int)

-}
get :
    String
    -> Json.Decode.Decoder a
    -> DataSource a
get url decoder =
    request
        ((\okUrl ->
            -- wrap in new variant
            { url = okUrl
            , method = "GET"
            , headers = []
            , body = emptyBody
            }
         )
            url
        )
        (expectJson decoder)


{-| The full details to perform a DataSource.Http request.
-}
type alias RequestDetails =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    }


requestToString : RequestDetails -> String
requestToString requestDetails =
    requestDetails.url


{-| Analogous to the `Expect` type in the `elm/http` package. This represents how you will process the data that comes
back in your DataSource.Http request.

You can derive `ExpectJson` from `ExpectString`. Or you could build your own helper to process the String
as XML, for example, or give an `elm-pages` build error if the response can't be parsed as XML.

-}
type Expect value
    = ExpectJson (Json.Decode.Decoder value)
    | ExpectString (String -> Result String value)
    | ExpectResponse (Response String -> value)
    | ExpectBytesResponse (Response Bytes -> value)
    | ExpectBytes (Bytes.Decode.Decoder value)
    | ExpectWhatever value


{-| Request a raw String. You can validate the String if you need to check the formatting, or try to parse it
in something besides JSON. Be sure to use the `DataSource.Http.request` function if you want an optimized request that
strips out unused JSON to optimize your asset size.

If the function you pass to `expectString` yields an `Err`, then you will get a build error that will
fail your `elm-pages` build and print out the String from the `Err`.

    request =
        DataSource.Http.unoptimizedRequest
            { url = "https://example.com/file.txt"
            , method = "GET"
            , headers = []
            , body = DataSource.Http.emptyBody
            }
            (DataSource.Http.expectString
                (\string ->
                    if String.toUpper string == string then
                        Ok string

                    else
                        Err "String was not uppercased"
                )
            )

-}
expectString : (String -> Result String value) -> Expect value
expectString =
    ExpectString


{-| Handle the incoming response as JSON and don't optimize the asset and strip out unused values.
Be sure to use the `DataSource.Http.request` function if you want an optimized request that
strips out unused JSON to optimize your asset size. This function makes sense to use for things like a GraphQL request
where the JSON payload is already trimmed down to the data you explicitly requested.

If the function you pass to `expectString` yields an `Err`, then you will get a build error that will
fail your `elm-pages` build and print out the String from the `Err`.

-}
expectJson : Json.Decode.Decoder value -> Expect value
expectJson =
    ExpectJson


{-| -}
expectBytes : Bytes.Decode.Decoder value -> Expect value
expectBytes =
    ExpectBytes


{-| -}
expectResponse : (Response String -> value) -> Expect value
expectResponse =
    ExpectResponse


{-| -}
expectWhatever : value -> Expect value
expectWhatever =
    ExpectWhatever


expectStringResponse : (Result error body -> msg) -> (Response String -> Result error body) -> Expect msg
expectStringResponse toMsg toResult_ =
    ExpectResponse (toResult_ >> toMsg)


{-| -}
expectBytesResponse : (Result error body -> msg) -> (Response Bytes -> Result error body) -> Expect msg
expectBytesResponse toMsg toResult_ =
    ExpectBytesResponse (toResult_ >> toMsg)


{-| Build a `DataSource.Http` request (analogous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `DataSource.Http` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [DataSource.Http.get](#get).
-}
internalRequest :
    { name : String
    , body : Body
    , expect : Expect a
    }
    -> DataSource a
internalRequest { name, body, expect } =
    request
        { url = "elm-pages-internal://" ++ name
        , method = "GET"
        , headers = []
        , body = body
        }
        expect


expectToString : Expect a -> String
expectToString expect =
    case expect of
        ExpectJson _ ->
            "ExpectJson"

        ExpectString _ ->
            "ExpectString"

        ExpectResponse _ ->
            "ExpectResponse"

        ExpectBytes _ ->
            "ExpectBytes"

        ExpectWhatever _ ->
            "ExpectWhatever"

        ExpectBytesResponse _ ->
            "ExpectBytesResponse"


{-| Build a `DataSource.Http` request (analogous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `DataSource.Http` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [DataSource.Http.get](#get).
-}
request :
    RequestDetails
    -> Expect a
    -> DataSource a
request request__ expect =
    let
        request_ : RequestDetails
        request_ =
            { request__
                | headers =
                    ( "elm-pages-internal", expectToString expect )
                        :: request__.headers
            }
    in
    Request
        [ request_ ]
        (\rawResponseDict ->
            rawResponseDict
                |> RequestsAndPending.get (request_ |> HashRequest.hash)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                Ok rawResponse

                            Nothing ->
                                Err (Pages.StaticHttpRequest.MissingHttpResponse (requestToString request_) [ request_ ])
                   )
                |> Result.andThen
                    (\(RequestsAndPending.Response maybeResponse body) ->
                        case ( expect, body, maybeResponse ) of
                            ( ExpectJson decoder, RequestsAndPending.JsonBody json, _ ) ->
                                json
                                    |> Json.Decode.decodeValue decoder
                                    |> Result.mapError
                                        (\error ->
                                            error
                                                |> Json.Decode.errorToString
                                                |> Pages.StaticHttpRequest.DecoderError
                                        )

                            ( ExpectString mapStringFn, RequestsAndPending.StringBody string, _ ) ->
                                string
                                    |> mapStringFn
                                    |> Result.mapError Pages.StaticHttpRequest.DecoderError

                            ( ExpectResponse mapResponse, RequestsAndPending.StringBody asStringBody, Just rawResponse ) ->
                                let
                                    asMetadata : Metadata
                                    asMetadata =
                                        { url = rawResponse.url
                                        , statusCode = rawResponse.statusCode
                                        , statusText = rawResponse.statusText
                                        , headers = rawResponse.headers
                                        }

                                    rawResponseToResponse : Response String
                                    rawResponseToResponse =
                                        if 200 <= rawResponse.statusCode && rawResponse.statusCode < 300 then
                                            GoodStatus_ asMetadata asStringBody

                                        else
                                            BadStatus_ asMetadata asStringBody
                                in
                                rawResponseToResponse
                                    |> mapResponse
                                    |> Ok

                            ( ExpectBytesResponse mapResponse, RequestsAndPending.BytesBody rawBytesBody, Just rawResponse ) ->
                                let
                                    asMetadata : Metadata
                                    asMetadata =
                                        { url = rawResponse.url
                                        , statusCode = rawResponse.statusCode
                                        , statusText = rawResponse.statusText
                                        , headers = rawResponse.headers
                                        }

                                    rawResponseToResponse : Response Bytes
                                    rawResponseToResponse =
                                        if 200 <= rawResponse.statusCode && rawResponse.statusCode < 300 then
                                            GoodStatus_ asMetadata rawBytesBody

                                        else
                                            BadStatus_ asMetadata rawBytesBody
                                in
                                rawResponseToResponse
                                    |> mapResponse
                                    |> Ok

                            ( ExpectBytes bytesDecoder, RequestsAndPending.BytesBody rawBytes, _ ) ->
                                rawBytes
                                    |> Bytes.Decode.decode bytesDecoder
                                    |> Result.fromMaybe
                                        (Pages.StaticHttpRequest.DecoderError
                                            "Bytes decoding failed."
                                        )

                            ( ExpectWhatever whateverValue, RequestsAndPending.WhateverBody, _ ) ->
                                Ok whateverValue

                            _ ->
                                Err
                                    (Pages.StaticHttpRequest.DecoderError
                                        "Internal error - unexpected body, expect, and raw response combination."
                                    )
                    )
                |> toResult
        )


type alias Metadata =
    { url : String
    , statusCode : Int
    , statusText : String
    , headers : Dict String String
    }


type Response body
    = BadUrl_ String
    | Timeout_
    | NetworkError_
    | BadStatus_ Metadata body
    | GoodStatus_ Metadata body


type Error
    = BadUrl String
    | Timeout
    | NetworkError
    | BadStatus Metadata String
    | BadBody String


toResult : Result Pages.StaticHttpRequest.Error b -> RawRequest b
toResult result =
    case result of
        Err error ->
            RequestError error

        Ok okValue ->
            ApiRoute okValue
