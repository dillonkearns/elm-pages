module BackendTask.Http exposing
    ( RequestDetails
    , get, request
    , Expect, expectString, expectJson, expectBytes, expectWhatever
    , withMetadata, Metadata
    , Error(..)
    , Body, emptyBody, stringBody, jsonBody
    , CacheStrategy(..), requestWithOptions, Options
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

@docs RequestDetails
@docs get, request


## Decoding Request Body

@docs Expect, expectString, expectJson, expectBytes, expectWhatever


## With Metadata

@docs withMetadata, Metadata


## Errors

@docs Error


## Building a BackendTask.Http Request Body

The way you build a body is analogous to the `elm/http` package. Currently, only `emptyBody` and
`stringBody` are supported. If you have a use case that calls for a different body type, please open a Github issue
and describe your use case!

@docs Body, emptyBody, stringBody, jsonBody


## Caching Options

@docs CacheStrategy, requestWithOptions, Options

-}

import BackendTask exposing (BackendTask)
import Base64
import Bytes.Decode
import Dict exposing (Dict)
import Exception exposing (Catchable)
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


{-| A simplified helper around [`BackendTask.Http.request`](#request), which builds up a BackendTask.Http GET request.

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode exposing (Decoder)

    getRequest : BackendTask Int
    getRequest =
        BackendTask.Http.get
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.field "stargazers_count" Decode.int)

-}
get :
    String
    -> Json.Decode.Decoder a
    -> BackendTask (Catchable Error) a
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


{-| The full details to perform a BackendTask.Http request.
-}
type alias RequestDetails =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    }


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
    RequestDetails
    -> Expect a
    -> BackendTask (Catchable Error) a
request request__ expect =
    let
        request_ : HashRequest.Request
        request_ =
            { url = request__.url
            , headers = request__.headers
            , method = request__.method
            , body = request__.body
            , useCache = Nothing
            }
    in
    requestRaw request_ expect


{-| -}
type CacheStrategy
    = UseGlobalDefault
    | IgnoreCache -- 'no-store'
    | ForceRevalidate -- 'no-cache'
    | ForceReload -- 'reload'
    | ForceCache -- 'force-cache'
    | ErrorUnlessCached -- 'only-if-cached'


{-| -}
requestWithOptions :
    RequestDetails
    -> Options
    -> Expect a
    -> BackendTask (Catchable Error) a
requestWithOptions request__ options expect =
    let
        request_ : HashRequest.Request
        request_ =
            { url = request__.url
            , headers = request__.headers
            , method = request__.method
            , body = request__.body
            , useCache = encodeOptions options |> Just
            }
    in
    requestRaw request_ expect


encodeOptions : Options -> Encode.Value
encodeOptions options =
    Encode.object
        ([ ( "cache"
           , (case options.cacheStrategy of
                UseGlobalDefault ->
                    Nothing

                IgnoreCache ->
                    Just "no-store"

                ForceRevalidate ->
                    Just "no-cache"

                ForceReload ->
                    Just "reload"

                ForceCache ->
                    Just "force-cache"

                ErrorUnlessCached ->
                    Just "only-if-cached"
             )
                |> Maybe.map Encode.string
           )
         , ( "retry", Encode.int options.retries |> Just )
         , ( "timeout", options.timeoutInMs |> Maybe.map Encode.int )
         ]
            |> List.filterMap
                (\( a, b ) -> b |> Maybe.map (Tuple.pair a))
        )


{-| -}
type alias Options =
    { cacheStrategy : CacheStrategy
    , retries : Int
    , timeoutInMs : Maybe Int
    }


{-| Build a `BackendTask.Http` request (analogous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `BackendTask.Http` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [BackendTask.Http.get](#get).
-}
requestRaw :
    HashRequest.Request
    -> Expect a
    -> BackendTask (Catchable Error) a
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
            , useCache = request__.useCache
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
                        Exception.Catchable error (errorToString error)
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
