module DataSource exposing
    ( DataSource
    , map, succeed, fail
    , fromResult
    , andThen, resolve, combine
    , andMap
    , map2, map3, map4, map5, map6, map7, map8, map9
    , mapError, onError
    )

{-| In an `elm-pages` app, each Route Module can define a value `data` which is a `DataSource` that will be resolved **before** `init` is called. That means it is also available
when the page's HTML is pre-rendered during the build step. You can also access the resolved data in `head` to use it for the page's SEO meta tags.

A `DataSource` lets you pull in data from:

  - Local files ([`DataSource.File`](DataSource-File))
  - HTTP requests ([`DataSource.Http`](DataSource-Http))
  - Globs, i.e. listing out local files based on a pattern like `content/*.txt` ([`DataSource.Glob`](DataSource-Glob))
  - Ports, i.e. getting JSON data from running custom NodeJS, similar to a port in a vanilla Elm app except run at build-time in NodeJS, rather than at run-time in the browser ([`DataSource.Port`](DataSource-Port))
  - Hardcoded data (`DataSource.succeed "Hello!"`)
  - Or any combination of the above, using `DataSource.map2`, `DataSource.andThen`, or other combining/continuing helpers from this module


## DataSource's vs. Effect's/Cmd's

DataSource's are always resolved before the page is rendered and sent to the browser. A DataSource is never executed
in the Browser. Instead, the resolved data from the DataSource is passed down to the Browser - it has been resolved
before any client-side JavaScript ever executes. In the case of a pre-rendered route, this is during the CLI build phase,
and for server-rendered routes its DataSource is resolved on the server.

Effect's/Cmd's are never executed on the CLI or server, they are only executed in the Browser. The data from a Route Module's
`init` function is used to render the initial HTML on the server or build step, but the Effect isn't executed and `update` is never called
before the page is hydrated in the Browser. This gives a deterministic mental model of what the first render will look like,
and a nicely typed way to define the initial `Data` you have to render your initial view.

Because `elm-pages` hydrates into a full Elm single-page app, it does need the data in order to initialize the Elm app.
So why not just get the data the old-fashioned way, with `elm/http`, for example?

A few reasons:

1.  DataSource's allow you to pull in data that you wouldn't normally be able to access from an Elm app, like local files, or listings of files in a folder. Not only that, but the dev server knows to automatically hot reload the data when the files it depends on change, so you can edit the files you used in your DataSource and see the page hot reload as you save!
2.  You can pre-render HTML for your pages, including the SEO meta tags, with all that rich, well-typed Elm data available! That's something you can't accomplish with a vanilla Elm app, and it's one of the main use cases for elm-pages.
3.  Because `elm-pages` has a build step, you know that your `DataSource.Http` requests succeeded, your decoders succeeded, your custom DataSource validations succeeded, and everything went smoothly. If something went wrong, you get a build failure and can deal with the issues before the site goes live. That means your users won't see those errors, and as a developer you don't need to handle those error cases in your code! Think of it as "parse, don't validate", but for your entire build. In the case of server-rendered routes, a DataSource failure will render a 500 page, so more care needs to be taken to make sure all common errors are handled properly, but the tradeoff is that you can use DataSource's to pull in highly dynamic data and even render user-specific pages.
4.  For static routes, you don't have to worry about an API being down, or hitting it repeatedly. You can build in data and it will end up as optimized binary-encoded data served up with all the other assets of your site. If your CDN (static site host) is down, then the rest of your site is probably down anyway. If your site host is up, then so is all of your `DataSource` data. Also, it will be served up extremely quickly without needing to wait for any database queries to be performed, `andThen` requests to be resolved, etc., because all of that work and waiting was done at build-time!


## Mental Model

You can think of a DataSource as a declarative (not imperative) definition of data. It represents where to get the data from, and how to transform it (map, combine with other DataSources, etc.).


## How do I actually use a DataSource?

This is very similar to Cmd's in Elm. You don't perform a Cmd just by running that code, as you might in a language like JavaScript. Instead, a Cmd _will not do anything_ unless you pass it to The Elm Architecture to have it perform it for you.
You pass a Cmd to The Elm Architecture by returning it in `init` or `update`. So actually a `Cmd` is just data describing a side-effect that the Elm runtime can perform, and how to build a `Msg` once it's done.

`DataSource`'s are very similar. A `DataSource` doesn't do anything just by "running" it. Just like a `Cmd`, it's only data that describes a side-effect to perform. Specifically, it describes a side-effect that the _elm-pages runtime_ can perform.
There are a few places where we can pass a `DataSource` to the `elm-pages` runtime so it can perform it. Most commonly, you give a field called `data` in your Route Module's definition. Instead of giving a `Msg` when the side-effects are complete,
the page will render once all of the side-effects have run and all the data is resolved. `elm-pages` makes the resolved data available your Route Module's `init`, `view`, `update`, and `head` functions, similar to how a regular Elm app passes `Msg`'s in
to `update`.

Any place in your `elm-pages` app where the framework lets you pass in a value of type `DataSource` is a place where you can give `elm-pages` a DataSource to perform (for example, `Site.head` where you define global head tags for your site).


## Basics

@docs DataSource

@docs map, succeed, fail

@docs fromResult


## Chaining Requests

@docs andThen, resolve, combine

@docs andMap

@docs map2, map3, map4, map5, map6, map7, map8, map9

-}

import Dict
import Pages.StaticHttpRequest exposing (RawRequest(..))


{-| A DataSource represents data that will be gathered at build time. Multiple `DataSource`s can be combined together using the `mapN` functions,
very similar to how you can manipulate values with Json Decoders in Elm.
-}
type alias DataSource error value =
    RawRequest error value


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
map : (a -> b) -> DataSource error a -> DataSource error b
map fn requestInfo =
    case requestInfo of
        ApiRoute value ->
            ApiRoute (Result.map fn value)

        Request urls lookupFn ->
            Request
                urls
                (mapLookupFn fn lookupFn)


mapLookupFn : (a -> b) -> (d -> c -> DataSource error a) -> d -> c -> DataSource error b
mapLookupFn fn lookupFn maybeMock requests =
    map fn (lookupFn maybeMock requests)


{-| Helper to remove an inner layer of Request wrapping.
-}
resolve : DataSource error (List (DataSource error value)) -> DataSource error (List value)
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
combine : List (DataSource error value) -> DataSource error (List value)
combine items =
    List.foldl (map2 (::)) (succeed []) items |> map List.reverse


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
map2 : (a -> b -> c) -> DataSource error a -> DataSource error b -> DataSource error c
map2 fn request1 request2 =
    -- elm-review: known-unoptimized-recursion
    -- TODO try to find a way to optimize tail-call recursion here
    case ( request1, request2 ) of
        ( ApiRoute value1, ApiRoute value2 ) ->
            ApiRoute (Result.map2 fn value1 value2)

        ( Request urls1 lookupFn1, Request urls2 lookupFn2 ) ->
            Request
                (urls1 ++ urls2)
                (\resolver responses ->
                    map2 fn
                        (lookupFn1 resolver responses)
                        (lookupFn2 resolver responses)
                )

        ( Request urls1 lookupFn1, ApiRoute value2 ) ->
            Request
                urls1
                (\resolver responses ->
                    map2 fn
                        (lookupFn1 resolver responses)
                        (ApiRoute value2)
                )

        ( ApiRoute value2, Request urls1 lookupFn1 ) ->
            Request
                urls1
                (\resolver responses ->
                    map2 fn
                        (ApiRoute value2)
                        (lookupFn1 resolver responses)
                )


{-| Build off of the response from a previous `DataSource` request to build a follow-up request. You can use the data
from the previous response to build up the URL, headers, etc. that you send to the subsequent request.

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    licenseData : DataSource String
    licenseData =
        DataSource.Http.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.at [ "license", "url" ] Decode.string)
            |> DataSource.andThen
                (\licenseUrl ->
                    DataSource.Http.get (Secrets.succeed licenseUrl) (Decode.field "description" Decode.string)
                )

-}
andThen : (a -> DataSource error b) -> DataSource error a -> DataSource error b
andThen fn requestInfo =
    -- elm-review: known-unoptimized-recursion
    -- TODO try to find a way to optimize recursion here
    case requestInfo of
        ApiRoute a ->
            case a of
                Ok okA ->
                    fn okA

                Err errA ->
                    fail errA

        Request urls lookupFn ->
            if List.isEmpty urls then
                andThen fn (lookupFn Nothing Dict.empty)

            else
                Request urls
                    (\maybeMockResolver responses ->
                        lookupFn maybeMockResolver responses
                            |> andThen fn
                    )


onError : (error -> DataSource mappedError value) -> DataSource error value -> DataSource mappedError value
onError fromError dataSource =
    case dataSource of
        ApiRoute a ->
            case a of
                Ok okA ->
                    succeed okA

                Err errA ->
                    fromError errA

        Request urls lookupFn ->
            if List.isEmpty urls then
                onError fromError (lookupFn Nothing Dict.empty)

            else
                Request urls
                    (\maybeMockResolver responses ->
                        lookupFn maybeMockResolver responses
                            |> onError fromError
                    )


{-| A helper for combining `DataSource`s in pipelines.
-}
andMap : DataSource error a -> DataSource error (a -> b) -> DataSource error b
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
succeed : a -> DataSource error a
succeed value =
    ApiRoute (Ok value)


{-| -}
fail : error -> DataSource error a
fail error =
    ApiRoute (Err error)


{-| Turn an Err into a DataSource failure.
-}
fromResult : Result error value -> DataSource error value
fromResult result =
    case result of
        Ok okValue ->
            succeed okValue

        Err error ->
            fail error


{-| -}
mapError : (error -> errorMapped) -> DataSource error value -> DataSource errorMapped value
mapError mapFn requestInfo =
    case requestInfo of
        ApiRoute value ->
            ApiRoute (Result.mapError mapFn value)

        Request urls lookupFn ->
            Request
                urls
                (mapLookupFnError mapFn lookupFn)


mapLookupFnError : (error -> errorMapped) -> (d -> c -> DataSource error a) -> d -> c -> DataSource errorMapped a
mapLookupFnError fn lookupFn maybeMock requests =
    mapError fn (lookupFn maybeMock requests)


{-| -}
mapError___ : Result error value -> DataSource error value
mapError___ result =
    case result of
        Ok okValue ->
            succeed okValue

        Err error ->
            fail error


{-| -}
map3 :
    (value1 -> value2 -> value3 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error valueCombined
map3 combineFn request1 request2 request3 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3


{-| -}
map4 :
    (value1 -> value2 -> value3 -> value4 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error valueCombined
map4 combineFn request1 request2 request3 request4 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4


{-| -}
map5 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error valueCombined
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
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error value6
    -> DataSource error valueCombined
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
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error value6
    -> DataSource error value7
    -> DataSource error valueCombined
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
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error value6
    -> DataSource error value7
    -> DataSource error value8
    -> DataSource error valueCombined
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
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error value6
    -> DataSource error value7
    -> DataSource error value8
    -> DataSource error value9
    -> DataSource error valueCombined
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
