module DataSource exposing
    ( DataSource
    , map, succeed, fail
    , fromResult
    , andThen, resolve, combine
    , andMap
    , map2, map3, map4, map5, map6, map7, map8, map9
    , distill, validate, distillCodec, distillSerializeCodec
    )

{-| In an `elm-pages` app, each page can define a value `data` which is a `DataSource` that will be resolved **before** `init` is called. That means it is also available
when the page's HTML is pre-rendered during the build step. You can also access the resolved data in `head` to use it for the page's SEO meta tags.

A `DataSource` lets you pull in data from:

  - Local files ([`DataSource.File`](DataSource-File))
  - HTTP requests ([`DataSource.Http`](DataSource-Http))
  - Globs, i.e. listing out local files based on a pattern like `content/*.txt` ([`DataSource.Glob`](DataSource-Glob))
  - Ports, i.e. getting JSON data from running custom NodeJS, similar to a port in a vanilla Elm app except run at build-time in NodeJS, rather than at run-time in the browser ([`DataSource.Port`](DataSource-Port))
  - Hardcoded data (`DataSource.succeed "Hello!"`)
  - Or any combination of the above, using `DataSource.map2`, `DataSource.andThen`, or other combining/continuing helpers from this module


## Where Does DataSource Data Come From?

Data from a `DataSource` is resolved when you load a page in the `elm-pages` dev server, or when you run `elm-pages build`.

Because `elm-pages` hydrates into a full Elm single-page app, it does need the data in order to initialize the Elm app.
So why not just get the data the old-fashioned way, with `elm/http`, for example?

A few reasons:

1.  DataSource's allow you to pull in data that you wouldn't normally be able to access from an Elm app, like local files, or listings of files in a folder. Not only that, but the dev server knows to automatically hot reload the data when the files it depends on change, so you can edit the files you used in your DataSource and see the page hot reload as you save!
2.  Because `elm-pages` has a build step, you know that your `DataSource.Http` requests succeeded, your decoders succeeded, your custom DataSource validations succeeded, and everything went smoothly. If something went wrong, you get a build failure and can deal with the issues before the site goes live. That means your users won't see those errors, and as a developer you don't need to handle those error cases in your code! Think of it as "parse, don't validate", but for your entire build.
3.  You don't have to worry about an API being down, or hitting it repeatedly. You can build in data and it will end up as JSON files served up with all the other assets of your site. If your CDN (static site host) is down, then the rest of your site is probably down anyway. If your site host is up, then so is all of your `DataSource` data. Also, it will be served up extremely quickly without needing to wait for any database queries to be performed, `andThen` requests to be resolved, etc., because all of that work and waiting was done at build-time!
4.  You can pre-render pages, including the SEO meta tags, with all that rich, well-typed Elm data available! That's something you can't accomplish with a vanilla Elm app, and it's one of the main use cases for elm-pages.

@docs DataSource

@docs map, succeed, fail

@docs fromResult


## Chaining Requests

@docs andThen, resolve, combine

@docs andMap

@docs map2, map3, map4, map5, map6, map7, map8, map9


## Optimizing Page Data

Distilling data lets you reduce the amount of data loaded on the client. You can also use it to perform computations at
build-time or server-request-time, store the result of the computation and then simply load that result on the client
without needing redo the computation again on the client.

@docs distill, validate, distillCodec, distillSerializeCodec


### Ensuring Unique Distill Keys

If you use the same string key for two different distilled values that have differing encoded JSON, then you
will get a build error (and an error in the dev server for that page). That means you can safely distill values
and let the build command tell you about these issues if they arise.

-}

import Codec
import Dict exposing (Dict)
import Dict.Extra
import Json.Decode as Decode
import Json.Encode as Encode
import KeepOrDiscard exposing (KeepOrDiscard)
import Pages.Internal.ApplicationType as ApplicationType exposing (ApplicationType)
import Pages.Internal.StaticHttpBody as Body
import Pages.Secrets
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (RawRequest(..), WhatToDo)
import RequestsAndPending exposing (RequestsAndPending)
import Serialize


{-| A DataSource represents data that will be gathered at build time. Multiple `DataSource`s can be combined together using the `mapN` functions,
very similar to how you can manipulate values with Json Decoders in Elm.
-}
type alias DataSource value =
    RawRequest value


{-| Transform a request into an arbitrary value. The same underlying HTTP requests will be performed during the build
step, but mapping allows you to change the resulting values by applying functions to the results.

A common use for this is to map your data into your elm-pages view:

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    view =
        DataSource.Http.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.field "stargazers_count" Decode.int)
            |> DataSource.map
                (\stars ->
                    { view =
                        \model viewForPage ->
                            { title = "Current stars: " ++ String.fromInt stars
                            , body = Html.text <| "⭐️ " ++ String.fromInt stars
                            , head = []
                            }
                    }
                )

-}
map : (a -> b) -> DataSource a -> DataSource b
map fn requestInfo =
    -- elm-review: known-unoptimized-recursion
    case requestInfo of
        RequestError error ->
            RequestError error

        Request partiallyStripped ( urls, lookupFn ) ->
            Request partiallyStripped
                ( urls
                , \keepOrDiscard appType rawResponses ->
                    map fn (lookupFn keepOrDiscard appType rawResponses)
                )

        Done stripped value ->
            Done stripped (fn value)


dontSaveData : DataSource a -> DataSource a
dontSaveData requestInfo =
    case requestInfo of
        RequestError _ ->
            requestInfo

        Request partiallyStripped ( urls, lookupFn ) ->
            Request partiallyStripped
                ( urls
                , \_ appType rawResponses ->
                    lookupFn KeepOrDiscard.Discard appType rawResponses
                )

        Done _ _ ->
            requestInfo


{-| This is the low-level `distill` function. In most cases, you'll want to use `distill` with a `Codec` from either
[`miniBill/elm-codec`](https://package.elm-lang.org/packages/miniBill/elm-codec/latest/) or
[`MartinSStewart/elm-serialize`](https://package.elm-lang.org/packages/MartinSStewart/elm-serialize/latest/)
-}
distill :
    String
    -> (raw -> Encode.Value)
    -> (Decode.Value -> Result String distilled)
    -> DataSource raw
    -> DataSource distilled
distill uniqueKey encode decode dataSource =
    -- elm-review: known-unoptimized-recursion
    case dataSource of
        RequestError error ->
            RequestError error

        Request partiallyStripped ( urls, lookupFn ) ->
            Request partiallyStripped
                ( urls
                , \_ appType rawResponses ->
                    case appType of
                        ApplicationType.Browser ->
                            rawResponses
                                |> RequestsAndPending.get uniqueKey
                                |> (\maybeResponse ->
                                        case maybeResponse of
                                            Just rawResponse ->
                                                rawResponse
                                                    |> Decode.decodeString Decode.value
                                                    |> Result.mapError Decode.errorToString
                                                    |> Result.andThen decode
                                                    |> Result.mapError Pages.StaticHttpRequest.DecoderError
                                                    |> Result.map (Tuple.pair Dict.empty)

                                            Nothing ->
                                                Err (Pages.StaticHttpRequest.MissingHttpResponse ("distill://" ++ uniqueKey) [])
                                   )
                                |> toResult

                        ApplicationType.Cli ->
                            lookupFn KeepOrDiscard.Discard appType rawResponses
                                |> distill uniqueKey encode decode
                )

        Done strippedResponses value ->
            Request
                (strippedResponses
                    |> Dict.insert
                        -- TODO should this include a prefix? Probably.
                        uniqueKey
                        (Pages.StaticHttpRequest.DistilledResponse (encode value))
                )
                ( []
                , \_ _ _ ->
                    value
                        |> encode
                        |> decode
                        |> fromResult
                )


{-| [`distill`](#distill) with a `Serialize.Codec` from [`MartinSStewart/elm-serialize`](https://package.elm-lang.org/packages/MartinSStewart/elm-serialize/latest).

    import DataSource
    import DataSource.Http
    import Secrets
    import Serialize

    millionRandomSum : DataSource Int
    millionRandomSum =
        DataSource.Http.get
            (Secrets.succeed "https://example.com/api/one-million-random-numbers.json")
            (Decode.list Decode.int)
            |> DataSource.map List.sum
            -- all of this expensive computation and data will happen before it hits the client!
            -- the user's browser simply loads up a single Int and runs an Int decoder to get it
            |> DataSource.distillSerializeCodec "million-random-sum" Serialize.int

If we didn't distill the data here, then all million Ints would have to be loaded in order to load the page.
The reason the data for these `DataSource`s needs to be loaded is that `elm-pages` hydrates into an Elm app. If it
output only HTML then we could build the HTML and throw away the data. But we need to ensure that the hydrated Elm app
has all the data that a page depends on, even if it the HTML for the page is also pre-rendered.

Using a `Codec` makes it safer to distill data because you know it is reversible.

-}
distillSerializeCodec :
    String
    -> Serialize.Codec error value
    -> DataSource value
    -> DataSource value
distillSerializeCodec uniqueKey serializeCodec =
    distill uniqueKey
        (Serialize.encodeToJson serializeCodec)
        (Serialize.decodeFromJson serializeCodec
            >> Result.mapError
                (\error ->
                    case error of
                        Serialize.DataCorrupted ->
                            "DataCorrupted"

                        Serialize.CustomError _ ->
                            "CustomError"

                        Serialize.SerializerOutOfDate ->
                            "SerializerOutOfDate"
                )
        )


{-| [`distill`](#distill) with a `Codec` from [`miniBill/elm-codec`](https://package.elm-lang.org/packages/miniBill/elm-codec/latest/).

    import Codec
    import DataSource
    import DataSource.Http
    import Secrets

    millionRandomSum : DataSource Int
    millionRandomSum =
        DataSource.Http.get
            (Secrets.succeed "https://example.com/api/one-million-random-numbers.json")
            (Decode.list Decode.int)
            |> DataSource.map List.sum
            -- all of this expensive computation and data will happen before it hits the client!
            -- the user's browser simply loads up a single Int and runs an Int decoder to get it
            |> DataSource.distillCodec "million-random-sum" Codec.int

If we didn't distill the data here, then all million Ints would have to be loaded in order to load the page.
The reason the data for these `DataSource`s needs to be loaded is that `elm-pages` hydrates into an Elm app. If it
output only HTML then we could build the HTML and throw away the data. But we need to ensure that the hydrated Elm app
has all the data that a page depends on, even if it the HTML for the page is also pre-rendered.

Using a `Codec` makes it safer to distill data because you know it is reversible.

-}
distillCodec :
    String
    -> Codec.Codec value
    -> DataSource value
    -> DataSource value
distillCodec uniqueKey codec =
    distill uniqueKey
        (Codec.encodeToValue codec)
        (Codec.decodeValue codec >> Result.mapError Decode.errorToString)


toResult : Result Pages.StaticHttpRequest.Error ( Dict String WhatToDo, b ) -> RawRequest b
toResult result =
    case result of
        Err error ->
            RequestError error

        Ok ( stripped, okValue ) ->
            Done stripped okValue


{-| -}
validate :
    (unvalidated -> validated)
    -> (unvalidated -> DataSource (Result String ()))
    -> DataSource unvalidated
    -> DataSource validated
validate markValidated validateDataSource unvalidatedDataSource =
    unvalidatedDataSource
        |> andThen
            (\unvalidated ->
                unvalidated
                    |> validateDataSource
                    |> andThen
                        (\result ->
                            case result of
                                Ok () ->
                                    succeed <| markValidated unvalidated

                                Err error ->
                                    fail error
                        )
                    |> dontSaveData
            )
        |> dontSaveData


{-| Helper to remove an inner layer of Request wrapping.
-}
resolve : DataSource (List (DataSource value)) -> DataSource (List value)
resolve =
    andThen combine


{-| Turn a list of `StaticHttp.Request`s into a single one.

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    type alias Pokemon =
        { name : String
        , sprite : String
        }

    pokemonDetailRequest : StaticHttp.Request (List Pokemon)
    pokemonDetailRequest =
        StaticHttp.get
            (Secrets.succeed "https://pokeapi.co/api/v2/pokemon/?limit=3")
            (Decode.field "results"
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.field "name" Decode.string)
                        (Decode.field "url" Decode.string)
                        |> Decode.map
                            (\( name, url ) ->
                                StaticHttp.get (Secrets.succeed url)
                                    (Decode.at
                                        [ "sprites", "front_default" ]
                                        Decode.string
                                        |> Decode.map (Pokemon name)
                                    )
                            )
                    )
                )
            )
            |> StaticHttp.andThen StaticHttp.combine

-}
combine : List (DataSource value) -> DataSource (List value)
combine =
    List.foldr (map2 (::)) (succeed [])


{-| Like map, but it takes in two `Request`s.

    view siteMetadata page =
        StaticHttp.map2
            (\elmPagesStars elmMarkdownStars ->
                { view =
                    \model viewForPage ->
                        { title = "Repo Stargazers"
                        , body = starsView elmPagesStars elmMarkdownStars
                        }
                , head = head elmPagesStars elmMarkdownStars
                }
            )
            (get
                (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
                (Decode.field "stargazers_count" Decode.int)
            )
            (get
                (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-markdown")
                (Decode.field "stargazers_count" Decode.int)
            )

-}
map2 : (a -> b -> c) -> DataSource a -> DataSource b -> DataSource c
map2 fn request1 request2 =
    -- elm-review: known-unoptimized-recursion
    case ( request1, request2 ) of
        ( RequestError error, _ ) ->
            RequestError error

        ( _, RequestError error ) ->
            RequestError error

        ( Request newDict1 ( urls1, lookupFn1 ), Request newDict2 ( urls2, lookupFn2 ) ) ->
            Request (combineReducedDicts newDict1 newDict2)
                ( urls1 ++ urls2
                , \keepOrDiscard appType rawResponses ->
                    map2 fn
                        (lookupFn1 keepOrDiscard appType rawResponses)
                        (lookupFn2 keepOrDiscard appType rawResponses)
                )

        ( Request dict1 ( urls1, lookupFn1 ), Done stripped2 value2 ) ->
            Request dict1
                ( urls1
                , \keepOrDiscard appType rawResponses ->
                    map2 fn
                        (lookupFn1 keepOrDiscard appType rawResponses)
                        (Done stripped2 value2)
                )

        ( Done stripped2 value2, Request dict1 ( urls1, lookupFn1 ) ) ->
            Request dict1
                ( urls1
                , \keepOrDiscard appType rawResponses ->
                    map2 fn
                        (Done stripped2 value2)
                        (lookupFn1 keepOrDiscard appType rawResponses)
                )

        ( Done stripped1 value1, Done stripped2 value2 ) ->
            Done
                (combineReducedDicts stripped1 stripped2)
                (fn value1 value2)


{-| Takes two dicts representing responses, some of which have been reduced, and picks the shorter of the two.
This is assuming that there are no duplicate URLs, so it can safely choose between either a raw or a reduced response.
It would not work correctly if it chose between two responses that were reduced with different `Json.Decode.Exploration.Decoder`s.
-}
combineReducedDicts : Dict String WhatToDo -> Dict String WhatToDo -> Dict String WhatToDo
combineReducedDicts dict1 dict2 =
    (Dict.toList dict1 ++ Dict.toList dict2)
        |> fromListDedupe Pages.StaticHttpRequest.merge


fromListDedupe : (comparable -> a -> a -> a) -> List ( comparable, a ) -> Dict comparable a
fromListDedupe combineFn xs =
    List.foldl
        (\( key, value ) acc -> Dict.Extra.insertDedupe (combineFn key) key value acc)
        Dict.empty
        xs


lookup : KeepOrDiscard -> ApplicationType -> DataSource value -> RequestsAndPending -> Result Pages.StaticHttpRequest.Error ( Dict String WhatToDo, value )
lookup =
    lookupHelp Dict.empty


lookupHelp : Dict String WhatToDo -> KeepOrDiscard -> ApplicationType -> DataSource value -> RequestsAndPending -> Result Pages.StaticHttpRequest.Error ( Dict String WhatToDo, value )
lookupHelp strippedSoFar keepOrDiscard appType requestInfo rawResponses =
    case requestInfo of
        RequestError error ->
            Err error

        Request strippedResponses ( urls, lookupFn ) ->
            lookupHelp (combineReducedDicts strippedResponses strippedSoFar)
                keepOrDiscard
                appType
                (addUrls urls (lookupFn keepOrDiscard appType rawResponses))
                rawResponses

        Done stripped value ->
            Ok ( combineReducedDicts stripped strippedSoFar, value )


addUrls : List (Pages.Secrets.Value HashRequest.Request) -> DataSource value -> DataSource value
addUrls urlsToAdd requestInfo =
    case requestInfo of
        RequestError error ->
            RequestError error

        Request stripped ( initialUrls, function ) ->
            Request stripped ( initialUrls ++ urlsToAdd, function )

        Done stripped value ->
            Done stripped value


{-| The full details to perform a StaticHttp request.
-}
type alias RequestDetails =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body.Body
    }


lookupUrls : DataSource value -> List (Pages.Secrets.Value RequestDetails)
lookupUrls requestInfo =
    case requestInfo of
        RequestError _ ->
            -- TODO should this have URLs passed through?
            []

        Request _ ( urls, _ ) ->
            urls

        Done _ _ ->
            []


{-| Build off of the response from a previous `StaticHttp` request to build a follow-up request. You can use the data
from the previous response to build up the URL, headers, etc. that you send to the subsequent request.

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    licenseData : StaticHttp.Request String
    licenseData =
        StaticHttp.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.at [ "license", "url" ] Decode.string)
            |> StaticHttp.andThen
                (\licenseUrl ->
                    StaticHttp.get (Secrets.succeed licenseUrl) (Decode.field "description" Decode.string)
                )

-}
andThen : (a -> DataSource b) -> DataSource a -> DataSource b
andThen fn requestInfo =
    -- TODO should this be non-empty Dict? Or should it be passed down some other way?
    Request Dict.empty
        ( lookupUrls requestInfo
        , \keepOrDiscard appType rawResponses ->
            lookup
                keepOrDiscard
                appType
                requestInfo
                rawResponses
                |> (\result ->
                        case result of
                            Err error ->
                                -- TODO should I pass through strippedResponses here?
                                --( strippedResponses, fn value )
                                RequestError error

                            Ok ( strippedResponses, value ) ->
                                case fn value of
                                    Request dict ( values, function ) ->
                                        Request (combineReducedDicts strippedResponses dict) ( values, function )

                                    RequestError error ->
                                        RequestError error

                                    Done dict finalValue ->
                                        Done (combineReducedDicts strippedResponses dict) finalValue
                   )
        )


{-| A helper for combining `DataSource`s in pipelines.
-}
andMap : DataSource a -> DataSource (a -> b) -> DataSource b
andMap =
    map2 (|>)


{-| This is useful for prototyping with some hardcoded data, or for having a view that doesn't have any StaticHttp data.

    import DataSource

    view :
        List ( PagePath, Metadata )
        ->
            { path : PagePath
            , frontmatter : Metadata
            }
        ->
            StaticHttp.Request
                { view : Model -> View -> { title : String, body : Html Msg }
                , head : List (Head.Tag Pages.PathKey)
                }
    view siteMetadata page =
        StaticHttp.succeed
            { view =
                \model viewForPage ->
                    mainView model viewForPage
            , head = head page.frontmatter
            }

-}
succeed : a -> DataSource a
succeed value =
    Request Dict.empty
        ( []
        , \_ _ _ ->
            Done Dict.empty value
        )


{-| Stop the StaticHttp chain with the given error message. If you reach a `fail` in your request,
you will get a build error. Or in the dev server, you will see the error message in an overlay in your browser (and in
the terminal).
-}
fail : String -> DataSource a
fail errorMessage =
    RequestError (Pages.StaticHttpRequest.UserCalledStaticHttpFail errorMessage)


{-| Turn an Err into a DataSource failure.
-}
fromResult : Result String value -> DataSource value
fromResult result =
    case result of
        Ok okValue ->
            succeed okValue

        Err error ->
            fail error


{-| -}
map3 :
    (value1 -> value2 -> value3 -> valueCombined)
    -> DataSource value1
    -> DataSource value2
    -> DataSource value3
    -> DataSource valueCombined
map3 combineFn request1 request2 request3 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3


{-| -}
map4 :
    (value1 -> value2 -> value3 -> value4 -> valueCombined)
    -> DataSource value1
    -> DataSource value2
    -> DataSource value3
    -> DataSource value4
    -> DataSource valueCombined
map4 combineFn request1 request2 request3 request4 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4


{-| -}
map5 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> valueCombined)
    -> DataSource value1
    -> DataSource value2
    -> DataSource value3
    -> DataSource value4
    -> DataSource value5
    -> DataSource valueCombined
map5 combineFn request1 request2 request3 request4 request5 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5


{-| -}
map6 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> valueCombined)
    -> DataSource value1
    -> DataSource value2
    -> DataSource value3
    -> DataSource value4
    -> DataSource value5
    -> DataSource value6
    -> DataSource valueCombined
map6 combineFn request1 request2 request3 request4 request5 request6 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6


{-| -}
map7 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> valueCombined)
    -> DataSource value1
    -> DataSource value2
    -> DataSource value3
    -> DataSource value4
    -> DataSource value5
    -> DataSource value6
    -> DataSource value7
    -> DataSource valueCombined
map7 combineFn request1 request2 request3 request4 request5 request6 request7 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7


{-| -}
map8 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> value8 -> valueCombined)
    -> DataSource value1
    -> DataSource value2
    -> DataSource value3
    -> DataSource value4
    -> DataSource value5
    -> DataSource value6
    -> DataSource value7
    -> DataSource value8
    -> DataSource valueCombined
map8 combineFn request1 request2 request3 request4 request5 request6 request7 request8 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7
        |> map2 (|>) request8


{-| -}
map9 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> value8 -> value9 -> valueCombined)
    -> DataSource value1
    -> DataSource value2
    -> DataSource value3
    -> DataSource value4
    -> DataSource value5
    -> DataSource value6
    -> DataSource value7
    -> DataSource value8
    -> DataSource value9
    -> DataSource valueCombined
map9 combineFn request1 request2 request3 request4 request5 request6 request7 request8 request9 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7
        |> map2 (|>) request8
        |> map2 (|>) request9
