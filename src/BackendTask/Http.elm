module BackendTask.Http exposing
    ( get, getJson
    , post
    , Expect, expectString, expectJson, expectBytes, expectWhatever
    , Error(..)
    , request
    , Body, emptyBody, stringBody, jsonBody, bytesBody
    , getWithOptions
    , CacheStrategy(..)
    , withMetadata, Metadata
    )

{-| `BackendTask.Http` requests are an alternative to doing Elm HTTP requests the traditional way using the `elm/http` package.

The key differences are:

  - `BackendTask.Http.Request`s are performed once at build time (`Http.Request`s are performed at runtime, at whenever point you perform them)
  - `BackendTask.Http.Request`s have a built-in `BackendTask.andThen` that allows you to perform follow-up requests without using tasks


## Scenarios where BackendTask.Http is a good fit

If you need data that is refreshed often you may want to do a traditional HTTP request with the `elm/http` package.
The kinds of situations that are served well by static HTTP are with data that updates moderately frequently or infrequently (or never).
A common pattern is to trigger a new build when data changes. Many JAMstack services
allow you to send a WebHook to your host (for example, Netlify is a good static file host that supports triggering builds with webhooks). So
you may want to have your site rebuild everytime your calendar feed has an event added, or whenever a page or article is added
or updated on a CMS service like Contentful.

In scenarios like this, you can serve data that is just as up-to-date as it would be using `elm/http`, but you get the performance
gains of using `BackendTask.Http.Request`s as well as the simplicity and robustness that comes with it. Read more about these benefits
in [this article introducing BackendTask.Http requests and some concepts around it](https://elm-pages.com/blog/static-http).


## Scenarios where BackendTask.Http is not a good fit

  - Data that is specific to the logged-in user
  - Data that needs to be the very latest and changes often (for example, sports scores)


## Making a Request

@docs get, getJson

@docs post


## Decoding Request Body

@docs Expect, expectString, expectJson, expectBytes, expectWhatever


## Error Handling

@docs Error


## General Requests

@docs request


## Building a BackendTask.Http Request Body

The way you build a body is analogous to the `elm/http` package. Currently, only `emptyBody` and
`stringBody` are supported. If you have a use case that calls for a different body type, please open a Github issue
and describe your use case!

@docs Body, emptyBody, stringBody, jsonBody, bytesBody


## Caching Options

`elm-pages` performs GET requests using a local HTTP cache by default. These requests are not performed using Elm's `elm/http`,
but rather are performed in NodeJS. Under the hood it uses [the NPM package `make-fetch-happen`](https://github.com/npm/make-fetch-happen).
Only GET requests made with `get`, `getJson`, or `getWithOptions` use local caching. Requests made with [`BackendTask.Http.request`](#request)
are not cached, even if the method is set to `GET`.

In dev mode, assets are cached more aggressively by default, whereas for a production build assets use a default to revalidate each cached response's freshness before using it (the `ForceRevalidate` [`CacheStrategy`](#CacheStrategy)).

The default caching behavior for GET requests is to use a local cache in `.elm-pages/http-cache`. This uses the same caching behavior
that browsers use to avoid re-downloading content when it hasn't changed. Servers can set HTTP response headers to explicitly control
this caching behavior.

  - [`cache-control` HTTP response headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) let you set a length of time before considering an asset stale. This could mean that the server considers it acceptable for an asset to be somewhat outdated, or this could mean that the asset is guaranteed to be up-to-date until it is stale - those semantics are up to the server.
  - `Last-Modified` and `ETag` HTTP response headers can be returned by the server allow [Conditional Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Conditional_requests). Conditional Requests let us send back the `Last-Modified` timestamp or `etag` hash for assets that are in our local cache to the server to check if the asset is fresh, and skip re-downloading it if it is unchanged (or download a fresh one otherwise).

It's important to note that depending on how the server sets these HTTP response headers, we may have outdated data - either because the server explicitly allows assets to become outdated with their cache-control headers, OR because cache-control headers are not set. When these headers aren't explicitly set, [clients are allowed to cache assets for 10% of the amount of time since it was last modified](https://httpwg.org/specs/rfc7234.html#heuristic.freshness).
For production builds, the default caching will ignore both the implicit and explicit information about an asset's freshness and _always_ revalidate it before using a locally cached response.

@docs getWithOptions

@docs CacheStrategy


## Including HTTP Metadata

@docs withMetadata, Metadata

-}

import BackendTask exposing (BackendTask)
import Base64
import Bytes exposing (Bytes)
import Bytes.Decode
import Dict exposing (Dict)
import Exception exposing (Exception)
import Json.Decode
import Json.Encode as Encode
import Pages.Internal.StaticHttpBody as Body
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (RawRequest(..))
import RequestsAndPending
import TerminalText


{-| Build an empty body for a BackendTask.Http request. See [elm/http's `Http.emptyBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#emptyBody).
-}
emptyBody : Body
emptyBody =
    Body.EmptyBody


{-| Build a body from `Bytes` for a BackendTask.Http request. See [elm/http's `Http.bytesBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#bytesBody).
-}
bytesBody : String -> Bytes -> Body
bytesBody =
    Body.BytesBody


{-| Builds a string body for a BackendTask.Http request. See [elm/http's `Http.stringBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#stringBody).

Note from the `elm/http` docs:

> The first argument is a [MIME type](https://en.wikipedia.org/wiki/Media_type) of the body. Some servers are strict about this!

-}
stringBody : String -> String -> Body
stringBody contentType content =
    Body.StringBody contentType content


{-| Builds a JSON body for a BackendTask.Http request. See [elm/http's `Http.jsonBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#jsonBody).
-}
jsonBody : Encode.Value -> Body
jsonBody content =
    Body.JsonBody content


{-| A body for a BackendTask.Http request.
-}
type alias Body =
    Body.Body


{-| A simplified helper around [`BackendTask.Http.get`](#get), which builds up a BackendTask.Http GET request with `expectJson`.

    import BackendTask
    import BackendTask.Http
    import Exception exposing (Exception)
    import Json.Decode as Decode exposing (Decoder)

    getRequest : BackendTask (Exception Error) Int
    getRequest =
        BackendTask.Http.getJson
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.field "stargazers_count" Decode.int)

-}
getJson :
    String
    -> Json.Decode.Decoder a
    -> BackendTask (Exception Error) a
getJson url decoder =
    getWithOptions
        { url = url
        , expect = expectJson decoder
        , headers = []
        , timeoutInMs = Nothing
        , retries = Nothing
        , cacheStrategy = Nothing
        , cachePath = Nothing
        }


{-| A simplified helper around [`BackendTask.Http.getWithOptions`](#getWithOptions), which builds up a GET request with
the default retries, timeout, and HTTP caching options. If you need to configure those options or include HTTP request headers,
use the more flexible `getWithOptions`.

    import BackendTask
    import BackendTask.Http
    import Exception exposing (Exception)

    getRequest : BackendTask (Exception Error) String
    getRequest =
        BackendTask.Http.get
            "https://api.github.com/repos/dillonkearns/elm-pages"
            BackendTask.Http.expectString

-}
get :
    String
    -> Expect a
    -> BackendTask (Exception Error) a
get url expect =
    getWithOptions
        { url = url
        , expect = expect
        , headers = []
        , timeoutInMs = Nothing
        , retries = Nothing
        , cacheStrategy = Nothing
        , cachePath = Nothing
        }


{-| Perform a GET request, with some additional options for the HTTP request, including options for caching behavior.

  - `retries` - Default is 0. Will try performing request again if set to a number greater than 0.
  - `timeoutInMs` - Default is no timeout.
  - `cacheStrategy` - The [caching options are passed to the NPM package `make-fetch-happen`](https://github.com/npm/make-fetch-happen#opts-cache)
  - `cachePath` - override the default directory for the local HTTP cache. This can be helpful if you want more granular control to clear some HTTP caches more or less frequently than others. Or you may want to preserve the local cache for some requests in your build server, but not store the cache for other requests.

-}
getWithOptions :
    { url : String
    , expect : Expect a
    , headers : List ( String, String )
    , cacheStrategy : Maybe CacheStrategy
    , retries : Maybe Int
    , timeoutInMs : Maybe Int
    , cachePath : Maybe String
    }
    -> BackendTask (Exception Error) a
getWithOptions request__ =
    let
        request_ : HashRequest.Request
        request_ =
            { url = request__.url
            , headers = request__.headers
            , body = emptyBody
            , method = "GET"
            , cacheOptions =
                { cacheStrategy = request__.cacheStrategy
                , retries = request__.retries
                , timeoutInMs = request__.timeoutInMs
                , cachePath = request__.cachePath
                }
                    |> encodeOptions
                    |> Just
            }
    in
    requestRaw request_ request__.expect


{-| -}
post :
    String
    -> Body
    -> Expect a
    -> BackendTask (Exception Error) a
post url body expect =
    request
        { url = url
        , method = "POST"
        , headers = []
        , body = body
        , retries = Nothing
        , timeoutInMs = Nothing
        }
        expect


{-| Analogous to the `Expect` type in the `elm/http` package. This represents how you will process the data that comes
back in your BackendTask.Http request.

You can derive `ExpectJson` from `ExpectString`. Or you could build your own helper to process the String
as XML, for example, or give an `elm-pages` build error if the response can't be parsed as XML.

-}
type Expect value
    = ExpectJson (Json.Decode.Decoder value)
    | ExpectString (String -> value)
    | ExpectBytes (Bytes.Decode.Decoder value)
    | ExpectWhatever value
    | ExpectMetadata (Metadata -> Expect value)


{-| Gives the HTTP response body as a raw String.

    import BackendTask exposing (BackendTask)
    import BackendTask.Http

    request : BackendTask String
    request =
        BackendTask.Http.request
            { url = "https://example.com/file.txt"
            , method = "GET"
            , headers = []
            , body = BackendTask.Http.emptyBody
            }
            BackendTask.Http.expectString

-}
expectString : Expect String
expectString =
    ExpectString identity


{-| Handle the incoming response as JSON and don't optimize the asset and strip out unused values.
Be sure to use the `BackendTask.Http.request` function if you want an optimized request that
strips out unused JSON to optimize your asset size. This function makes sense to use for things like a GraphQL request
where the JSON payload is already trimmed down to the data you explicitly requested.

If the function you pass to `expectString` yields an `Err`, then you will get a build error that will
fail your `elm-pages` build and print out the String from the `Err`.

-}
expectJson : Json.Decode.Decoder value -> Expect value
expectJson =
    ExpectJson


{-| -}
withMetadata : (Metadata -> value -> combined) -> Expect value -> Expect combined
withMetadata combineFn originalExpect =
    -- known-unoptimized-recursion
    case originalExpect of
        ExpectJson jsonDecoder ->
            ExpectMetadata (\metadata -> ExpectJson (jsonDecoder |> Json.Decode.map (combineFn metadata)))

        ExpectString stringToValue ->
            ExpectMetadata
                (\metadata ->
                    ExpectString (\string -> string |> stringToValue |> combineFn metadata)
                )

        ExpectBytes bytesDecoder ->
            ExpectMetadata (\metadata -> ExpectBytes (bytesDecoder |> Bytes.Decode.map (combineFn metadata)))

        ExpectWhatever value ->
            ExpectMetadata (\metadata -> ExpectWhatever (combineFn metadata value))

        ExpectMetadata metadataToExpect ->
            ExpectMetadata (\metadata -> withMetadata combineFn (metadataToExpect metadata))


{-| -}
expectBytes : Bytes.Decode.Decoder value -> Expect value
expectBytes =
    ExpectBytes


{-| -}
expectWhatever : value -> Expect value
expectWhatever =
    ExpectWhatever


expectToString : Expect a -> String
expectToString expect =
    -- known-unoptimized-recursion
    case expect of
        ExpectJson _ ->
            "ExpectJson"

        ExpectString _ ->
            "ExpectString"

        ExpectBytes _ ->
            "ExpectBytes"

        ExpectWhatever _ ->
            "ExpectWhatever"

        ExpectMetadata toExpect ->
            -- It's safe to call this with fake metadata to get the kind of Expect because the exposed
            -- API, `withMetadata`, will never change the type of Expect it returns based on the metadata, it simply
            -- wraps the Expect with the additional Metadata.
            -- It's important not to expose the raw `ExpectMetadata` constructor however because that would break that guarantee.
            toExpect
                { url = ""
                , statusCode = 123
                , statusText = ""
                , headers = Dict.empty
                }
                |> expectToString


{-| -}
request :
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    , retries : Maybe Int
    , timeoutInMs : Maybe Int
    }
    -> Expect a
    -> BackendTask (Exception Error) a
request request__ expect =
    let
        request_ : HashRequest.Request
        request_ =
            { url = request__.url
            , headers = request__.headers
            , method = request__.method
            , body = request__.body
            , cacheOptions =
                { cacheStrategy = Nothing -- cache strategy only applies to GET and HEAD, need to use getWithOptions to customize
                , cachePath = Nothing
                , retries = request__.retries
                , timeoutInMs = request__.timeoutInMs
                }
                    |> encodeOptions
                    |> Just
            }
    in
    requestRaw request_ expect


{-| -}
type CacheStrategy
    = IgnoreCache -- 'no-store'
    | ForceRevalidate -- 'no-cache'
    | ForceReload -- 'reload'
    | ForceCache -- 'force-cache'
    | ErrorUnlessCached -- 'only-if-cached'


encodeOptions :
    { cacheStrategy : Maybe CacheStrategy
    , cachePath : Maybe String
    , retries : Maybe Int
    , timeoutInMs : Maybe Int
    }
    -> Encode.Value
encodeOptions options =
    Encode.object
        ([ ( "cache"
           , options.cacheStrategy
                |> Maybe.map
                    (\cacheStrategy ->
                        case cacheStrategy of
                            IgnoreCache ->
                                "no-store"

                            ForceRevalidate ->
                                "no-cache"

                            ForceReload ->
                                "reload"

                            ForceCache ->
                                "force-cache"

                            ErrorUnlessCached ->
                                "only-if-cached"
                    )
                |> Maybe.map Encode.string
           )
         , ( "retry", options.retries |> Maybe.map Encode.int )
         , ( "timeout", options.timeoutInMs |> Maybe.map Encode.int )
         , ( "cachePath", options.cachePath |> Maybe.map Encode.string )
         ]
            |> List.filterMap
                (\( a, b ) -> b |> Maybe.map (Tuple.pair a))
        )


{-| Build a `BackendTask.Http` request (analogous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `BackendTask.Http` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [BackendTask.Http.get](#get).
-}
requestRaw :
    HashRequest.Request
    -> Expect a
    -> BackendTask (Exception Error) a
requestRaw request__ expect =
    let
        request_ : HashRequest.Request
        request_ =
            { url = request__.url
            , headers =
                ( "elm-pages-internal", expectToString expect )
                    :: request__.headers
            , method = request__.method
            , body = request__.body
            , cacheOptions = request__.cacheOptions
            }
    in
    Request
        [ request_ ]
        (\maybeMockResolver rawResponseDict ->
            (case maybeMockResolver of
                Just mockResolver ->
                    mockResolver request_

                Nothing ->
                    rawResponseDict |> RequestsAndPending.get (request_ |> HashRequest.hash)
            )
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                Ok rawResponse

                            Nothing ->
                                --Err (Pages.StaticHttpRequest.UserCalledStaticHttpFail ("INTERNAL ERROR - expected request" ++ request_.url))
                                Err (BadBody Nothing ("INTERNAL ERROR - expected request" ++ request_.url))
                   )
                |> Result.andThen
                    (\(RequestsAndPending.Response maybeResponse body) ->
                        let
                            maybeBadResponse : Maybe Error
                            maybeBadResponse =
                                case maybeResponse of
                                    Just response ->
                                        if not (response.statusCode >= 200 && response.statusCode < 300) then
                                            case body of
                                                RequestsAndPending.StringBody s ->
                                                    BadStatus
                                                        { url = response.url
                                                        , statusCode = response.statusCode
                                                        , statusText = response.statusText
                                                        , headers = response.headers
                                                        }
                                                        s
                                                        |> Just

                                                RequestsAndPending.BytesBody bytes ->
                                                    BadStatus
                                                        { url = response.url
                                                        , statusCode = response.statusCode
                                                        , statusText = response.statusText
                                                        , headers = response.headers
                                                        }
                                                        (Base64.fromBytes bytes |> Maybe.withDefault "")
                                                        |> Just

                                                RequestsAndPending.JsonBody value ->
                                                    BadStatus
                                                        { url = response.url
                                                        , statusCode = response.statusCode
                                                        , statusText = response.statusText
                                                        , headers = response.headers
                                                        }
                                                        (Encode.encode 0 value)
                                                        |> Just

                                                RequestsAndPending.WhateverBody ->
                                                    BadStatus
                                                        { url = response.url
                                                        , statusCode = response.statusCode
                                                        , statusText = response.statusText
                                                        , headers = response.headers
                                                        }
                                                        ""
                                                        |> Just

                                        else
                                            Nothing

                                    Nothing ->
                                        Nothing
                        in
                        case maybeBadResponse of
                            Just badResponse ->
                                Err badResponse

                            Nothing ->
                                toResultThing ( expect, body, maybeResponse )
                    )
                |> BackendTask.fromResult
                |> BackendTask.mapError
                    (\error ->
                        Exception.Exception error (errorToString error)
                    )
        )


toResultThing :
    ( Expect value
    , RequestsAndPending.ResponseBody
    , Maybe RequestsAndPending.RawResponse
    )
    -> Result Error value
toResultThing ( expect, body, maybeResponse ) =
    case ( expect, body, maybeResponse ) of
        ( ExpectMetadata toExpect, _, Just rawResponse ) ->
            let
                asMetadata : Metadata
                asMetadata =
                    { url = rawResponse.url
                    , statusCode = rawResponse.statusCode
                    , statusText = rawResponse.statusText
                    , headers = rawResponse.headers
                    }
            in
            toResultThing ( toExpect asMetadata, body, maybeResponse )

        ( ExpectJson decoder, RequestsAndPending.JsonBody json, _ ) ->
            json
                |> Json.Decode.decodeValue decoder
                |> Result.mapError
                    (\error ->
                        error
                            |> Json.Decode.errorToString
                            |> BadBody (Just error)
                    )

        ( ExpectString mapStringFn, RequestsAndPending.StringBody string, _ ) ->
            string
                |> mapStringFn
                |> Ok

        ( ExpectBytes bytesDecoder, RequestsAndPending.BytesBody rawBytes, _ ) ->
            rawBytes
                |> Bytes.Decode.decode bytesDecoder
                |> Result.fromMaybe
                    (BadBody Nothing "Bytes decoding failed.")

        ( ExpectWhatever whateverValue, RequestsAndPending.WhateverBody, _ ) ->
            Ok whateverValue

        _ ->
            Err (BadBody Nothing "Unexpected combination, internal error")


errorToString : Error -> { title : String, body : String }
errorToString error =
    { title = "HTTP Error"
    , body =
        (case error of
            BadUrl string ->
                [ TerminalText.text ("BadUrl " ++ string)
                ]

            Timeout ->
                [ TerminalText.text "Timeout"
                ]

            NetworkError ->
                [ TerminalText.text "NetworkError"
                ]

            BadStatus _ string ->
                [ TerminalText.text ("BadStatus: " ++ string)
                ]

            BadBody _ string ->
                [ TerminalText.text ("BadBody: " ++ string)
                ]
        )
            |> TerminalText.toString
    }


{-| -}
type alias Metadata =
    { url : String
    , statusCode : Int
    , statusText : String
    , headers : Dict String String
    }


{-| -}
type Error
    = BadUrl String
    | Timeout
    | NetworkError
    | BadStatus Metadata String
    | BadBody (Maybe Json.Decode.Error) String
