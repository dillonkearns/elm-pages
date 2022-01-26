module DataSource.Http exposing
    ( RequestDetails
    , get, request
    , Body, emptyBody, stringBody, jsonBody
    , unoptimizedRequest
    , Expect, expectString, expectUnoptimizedJson
    )

{-| `DataSource.Http` requests are an alternative to doing Elm HTTP requests the traditional way using the `elm/http` package.

The key differences are:

  - `DataSource.Http.Request`s are performed once at build time (`Http.Request`s are performed at runtime, at whenever point you perform them)
  - `DataSource.Http.Request`s strip out unused JSON data from the data your decoder doesn't touch to minimize the JSON payload
  - `DataSource.Http.Request`s can use [`Pages.Secrets`](Pages.Secrets) to securely use credentials from your environment variables which are completely masked in the production assets.
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


## Building a DataSource.Http Request Body

The way you build a body is analogous to the `elm/http` package. Currently, only `emptyBody` and
`stringBody` are supported. If you have a use case that calls for a different body type, please open a Github issue
and describe your use case!

@docs Body, emptyBody, stringBody, jsonBody


## Unoptimized Requests

Warning - use these at your own risk! It's highly recommended that you use the other request functions that make use of
`zwilias/json-decode-exploration` in order to allow you to reduce down your JSON to only the values that are used by
your decoders. This can significantly reduce download sizes for your DataSource.Http requests.

@docs unoptimizedRequest


### Expect for unoptimized requests

@docs Expect, expectString, expectUnoptimizedJson

-}

import DataSource exposing (DataSource)
import Dict
import Internal.OptimizedDecoder
import Json.Decode
import Json.Decode.Exploration
import Json.Encode as Encode
import KeepOrDiscard
import OptimizedDecoder as Decode exposing (Decoder)
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.StaticHttpBody as Body
import Pages.Secrets
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (RawRequest(..))
import RequestsAndPending
import Secrets


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
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.field "stargazers_count" Decode.int)

-}
get :
    Pages.Secrets.Value String
    -> Decoder a
    -> DataSource a
get url decoder =
    request
        (Secrets.map
            (\okUrl ->
                -- wrap in new variant
                { url = okUrl
                , method = "GET"
                , headers = []
                , body = emptyBody
                }
            )
            url
        )
        decoder


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


{-| Build a `DataSource.Http` request (analagous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `DataSource.Http` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [DataSource.Http.get](#get).
-}
request :
    Pages.Secrets.Value RequestDetails
    -> Decoder a
    -> DataSource a
request urlWithSecrets decoder =
    unoptimizedRequest urlWithSecrets (ExpectJson decoder)


{-| Analogous to the `Expect` type in the `elm/http` package. This represents how you will process the data that comes
back in your DataSource.Http request.

You can derive `ExpectUnoptimizedJson` from `ExpectString`. Or you could build your own helper to process the String
as XML, for example, or give an `elm-pages` build error if the response can't be parsed as XML.

-}
type Expect value
    = ExpectUnoptimizedJson (Json.Decode.Decoder value)
    | ExpectJson (Decoder value)
    | ExpectString (String -> Result String value)


{-| Request a raw String. You can validate the String if you need to check the formatting, or try to parse it
in something besides JSON. Be sure to use the `DataSource.Http.request` function if you want an optimized request that
strips out unused JSON to optimize your asset size.

If the function you pass to `expectString` yields an `Err`, then you will get a build error that will
fail your `elm-pages` build and print out the String from the `Err`.

    request =
        DataSource.Http.unoptimizedRequest
            (Secrets.succeed
                { url = "https://example.com/file.txt"
                , method = "GET"
                , headers = []
                , body = DataSource.Http.emptyBody
                }
            )
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
expectUnoptimizedJson : Json.Decode.Decoder value -> Expect value
expectUnoptimizedJson =
    ExpectUnoptimizedJson


{-| This is an alternative to the other request functions in this module that doesn't perform any optimizations on the
asset. Be sure to use the optimized versions, like `DataSource.Http.request`, if you can. Using those can significantly reduce
your asset sizes by removing all unused fields from your JSON.

You may want to use this function instead if you need XML data or plaintext. Or maybe you're hitting a GraphQL API,
so you don't need any additional optimization as the payload is already reduced down to exactly what you requested.

-}
unoptimizedRequest :
    Pages.Secrets.Value RequestDetails
    -> Expect a
    -> DataSource a
unoptimizedRequest requestWithSecrets expect =
    case expect of
        ExpectJson decoder ->
            Request Dict.empty
                ( [ requestWithSecrets ]
                , \keepOrDiscard appType rawResponseDict ->
                    case appType of
                        ApplicationType.Cli ->
                            rawResponseDict
                                |> RequestsAndPending.get (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                |> (\maybeResponse ->
                                        case maybeResponse of
                                            Just rawResponse ->
                                                Ok
                                                    ( Dict.singleton (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                                        (case keepOrDiscard of
                                                            KeepOrDiscard.Keep ->
                                                                Pages.StaticHttpRequest.UseRawResponse

                                                            KeepOrDiscard.Discard ->
                                                                Pages.StaticHttpRequest.CliOnly
                                                        )
                                                    , rawResponse
                                                    )

                                            Nothing ->
                                                Err
                                                    (Pages.StaticHttpRequest.MissingHttpResponse
                                                        (requestToString (Secrets.maskedLookup requestWithSecrets))
                                                        [ requestWithSecrets ]
                                                    )
                                   )
                                |> Result.andThen
                                    (\( strippedResponses, rawResponse ) ->
                                        rawResponse
                                            |> Json.Decode.Exploration.decodeString (decoder |> Internal.OptimizedDecoder.jde)
                                            |> (\decodeResult ->
                                                    case decodeResult of
                                                        Json.Decode.Exploration.BadJson ->
                                                            Pages.StaticHttpRequest.DecoderError ("Payload sent back invalid JSON\n" ++ rawResponse) |> Err

                                                        Json.Decode.Exploration.Errors errors ->
                                                            errors
                                                                |> Json.Decode.Exploration.errorsToString
                                                                |> Pages.StaticHttpRequest.DecoderError
                                                                |> Err

                                                        Json.Decode.Exploration.WithWarnings _ a ->
                                                            Ok a

                                                        Json.Decode.Exploration.Success a ->
                                                            Ok a
                                               )
                                            |> Result.map
                                                (\finalRequest ->
                                                    ( case keepOrDiscard of
                                                        KeepOrDiscard.Keep ->
                                                            strippedResponses
                                                                |> Dict.insert
                                                                    (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                                                    Pages.StaticHttpRequest.UseRawResponse

                                                        KeepOrDiscard.Discard ->
                                                            strippedResponses
                                                                |> Dict.insert
                                                                    (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                                                    Pages.StaticHttpRequest.CliOnly
                                                    , finalRequest
                                                    )
                                                )
                                    )
                                |> toResult

                        ApplicationType.Browser ->
                            rawResponseDict
                                |> RequestsAndPending.get (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                |> (\maybeResponse ->
                                        case maybeResponse of
                                            Just rawResponse ->
                                                Ok
                                                    ( -- TODO should this be an empty Dict? Shouldn't matter in the browser.
                                                      Dict.singleton (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                                        Pages.StaticHttpRequest.UseRawResponse
                                                    , rawResponse
                                                    )

                                            Nothing ->
                                                Err
                                                    (Pages.StaticHttpRequest.MissingHttpResponse (requestToString (Secrets.maskedLookup requestWithSecrets))
                                                        [ requestWithSecrets ]
                                                    )
                                   )
                                |> Result.andThen
                                    (\( strippedResponses, rawResponse ) ->
                                        rawResponse
                                            |> Json.Decode.decodeString (decoder |> Internal.OptimizedDecoder.jd)
                                            |> (\decodeResult ->
                                                    case decodeResult of
                                                        Err error ->
                                                            Pages.StaticHttpRequest.DecoderError
                                                                ("Payload sent back invalid JSON\n"
                                                                    ++ rawResponse
                                                                    ++ "\n KEYS"
                                                                    ++ (Dict.keys strippedResponses |> String.join " - ")
                                                                    ++ Json.Decode.errorToString error
                                                                )
                                                                |> Err

                                                        Ok a ->
                                                            Ok a
                                               )
                                            |> Result.map
                                                (\finalRequest ->
                                                    ( strippedResponses
                                                    , finalRequest
                                                    )
                                                )
                                    )
                                |> toResult
                )

        ExpectUnoptimizedJson decoder ->
            Request Dict.empty
                ( [ requestWithSecrets ]
                , \_ _ rawResponseDict ->
                    rawResponseDict
                        |> RequestsAndPending.get (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                        |> (\maybeResponse ->
                                case maybeResponse of
                                    Just rawResponse ->
                                        Ok
                                            ( -- TODO check keepOrDiscard
                                              Dict.singleton (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                                Pages.StaticHttpRequest.UseRawResponse
                                            , rawResponse
                                            )

                                    Nothing ->
                                        Err
                                            (Pages.StaticHttpRequest.MissingHttpResponse (requestToString (Secrets.maskedLookup requestWithSecrets))
                                                [ requestWithSecrets ]
                                            )
                           )
                        |> Result.andThen
                            (\( strippedResponses, rawResponse ) ->
                                rawResponse
                                    |> Json.Decode.decodeString decoder
                                    |> (\decodeResult ->
                                            case decodeResult of
                                                Err error ->
                                                    error
                                                        |> Decode.errorToString
                                                        |> Pages.StaticHttpRequest.DecoderError
                                                        |> Err

                                                Ok a ->
                                                    Ok a
                                       )
                                    |> Result.map
                                        (\finalRequest ->
                                            ( -- TODO check keepOrDiscard
                                              strippedResponses
                                                |> Dict.insert
                                                    (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                                                    Pages.StaticHttpRequest.UseRawResponse
                                            , finalRequest
                                            )
                                        )
                            )
                        |> toResult
                )

        ExpectString mapStringFn ->
            Request Dict.empty
                ( [ requestWithSecrets ]
                , \_ _ rawResponseDict ->
                    rawResponseDict
                        |> RequestsAndPending.get (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash)
                        |> (\maybeResponse ->
                                case maybeResponse of
                                    Just rawResponse ->
                                        Ok
                                            ( -- TODO check keepOrDiscard
                                              Dict.singleton (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash) Pages.StaticHttpRequest.UseRawResponse
                                            , rawResponse
                                            )

                                    Nothing ->
                                        Err
                                            (Pages.StaticHttpRequest.MissingHttpResponse (requestToString (Secrets.maskedLookup requestWithSecrets))
                                                [ requestWithSecrets ]
                                            )
                           )
                        |> Result.andThen
                            (\( strippedResponses, rawResponse ) ->
                                rawResponse
                                    |> mapStringFn
                                    |> Result.mapError Pages.StaticHttpRequest.DecoderError
                                    |> Result.map
                                        (\finalRequest ->
                                            ( -- TODO check keepOrDiscard
                                              strippedResponses
                                                |> Dict.insert (Secrets.maskedLookup requestWithSecrets |> HashRequest.hash) Pages.StaticHttpRequest.UseRawResponse
                                            , finalRequest
                                            )
                                        )
                            )
                        |> toResult
                )


toResult : Result Pages.StaticHttpRequest.Error ( Dict.Dict String Pages.StaticHttpRequest.WhatToDo, b ) -> RawRequest b
toResult result =
    case result of
        Err error ->
            RequestError error

        Ok ( stripped, okValue ) ->
            ApiRoute stripped okValue
