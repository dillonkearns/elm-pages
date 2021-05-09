module DataSource exposing
    ( DataSource
    , map, succeed, fail
    , fromResult
    , Body, emptyBody, stringBody, jsonBody
    , andThen, resolve, combine
    , map2, map3, map4, map5, map6, map7, map8, map9
    )

{-| StaticHttp requests are an alternative to doing Elm HTTP requests the traditional way using the `elm/http` package.

The key differences are:

  - `StaticHttp.Request`s are performed once at build time (`Http.Request`s are performed at runtime, at whenever point you perform them)
  - `StaticHttp.Request`s strip out unused JSON data from the data your decoder doesn't touch to minimize the JSON payload
  - `StaticHttp.Request`s can use [`Pages.Secrets`](Pages.Secrets) to securely use credentials from your environment variables which are completely masked in the production assets.
  - `StaticHttp.Request`s have a built-in `StaticHttp.andThen` that allows you to perform follow-up requests without using tasks


## Scenarios where StaticHttp is a good fit

If you need data that is refreshed often you may want to do a traditional HTTP request with the `elm/http` package.
The kinds of situations that are served well by static HTTP are with data that updates moderately frequently or infrequently (or never).
A common pattern is to trigger a new build when data changes. Many JAMstack services
allow you to send a WebHook to your host (for example, Netlify is a good static file host that supports triggering builds with webhooks). So
you may want to have your site rebuild everytime your calendar feed has an event added, or whenever a page or article is added
or updated on a CMS service like Contentful.

In scenarios like this, you can serve data that is just as up-to-date as it would be using `elm/http`, but you get the performance
gains of using `StaticHttp.Request`s as well as the simplicity and robustness that comes with it. Read more about these benefits
in [this article introducing StaticHttp requests and some concepts around it](https://elm-pages.com/blog/static-http).


## Scenarios where StaticHttp is not a good fit

  - Data that is specific to the logged-in user
  - Data that needs to be the very latest and changes often (for example, sports scores)

@docs DataSource

@docs map, succeed, fail

@docs fromResult


## Building a StaticHttp Request Body

The way you build a body is analogous to the `elm/http` package. Currently, only `emptyBody` and
`stringBody` are supported. If you have a use case that calls for a different body type, please open a Github issue
and describe your use case!

@docs Body, emptyBody, stringBody, jsonBody


## Chaining Requests

@docs andThen, resolve, combine

@docs map2, map3, map4, map5, map6, map7, map8, map9

-}

import Dict exposing (Dict)
import Dict.Extra
import Json.Encode as Encode
import Pages.Internal.ApplicationType exposing (ApplicationType)
import Pages.Internal.StaticHttpBody as Body
import Pages.Secrets
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (RawRequest(..))
import RequestsAndPending exposing (RequestsAndPending)


{-| Build an empty body for a StaticHttp request. See [elm/http's `Http.emptyBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#emptyBody).
-}
emptyBody : Body
emptyBody =
    Body.EmptyBody


{-| Builds a string body for a StaticHttp request. See [elm/http's `Http.stringBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#stringBody).

Note from the `elm/http` docs:

> The first argument is a [MIME type](https://en.wikipedia.org/wiki/Media_type) of the body. Some servers are strict about this!

-}
stringBody : String -> String -> Body
stringBody contentType content =
    Body.StringBody contentType content


{-| Builds a JSON body for a StaticHttp request. See [elm/http's `Http.jsonBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#jsonBody).
-}
jsonBody : Encode.Value -> Body
jsonBody content =
    Body.JsonBody content


{-| A body for a StaticHttp request.
-}
type alias Body =
    Body.Body


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
        StaticHttp.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.field "stargazers_count" Decode.int)
            |> StaticHttp.map
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
    case requestInfo of
        Request ( urls, lookupFn ) ->
            Request
                ( urls
                , \appType rawResponses ->
                    lookupFn appType rawResponses
                        |> Result.map
                            (\( partiallyStripped, nextRequest ) ->
                                ( partiallyStripped, map fn nextRequest )
                            )
                )

        Done value ->
            fn value |> Done


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
    List.foldl (map2 (::)) (succeed [])


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
    case ( request1, request2 ) of
        ( Request ( urls1, lookupFn1 ), Request ( urls2, lookupFn2 ) ) ->
            let
                value : ApplicationType -> RequestsAndPending -> Result Pages.StaticHttpRequest.Error ( Dict String String, DataSource c )
                value appType rawResponses =
                    case ( lookupFn1 appType rawResponses, lookupFn2 appType rawResponses ) of
                        ( Ok ( newDict1, newValue1 ), Ok ( newDict2, newValue2 ) ) ->
                            Ok ( combineReducedDicts newDict1 newDict2, map2 fn newValue1 newValue2 )

                        ( Err error, _ ) ->
                            Err error

                        ( _, Err error ) ->
                            Err error
            in
            Request
                ( urls1 ++ urls2
                , value
                )

        ( Request ( urls1, lookupFn1 ), Done value2 ) ->
            Request
                ( urls1
                , \appType rawResponses ->
                    lookupFn1 appType rawResponses
                        |> Result.map
                            (\( dict1, value1 ) ->
                                ( dict1, map2 fn value1 (Done value2) )
                            )
                )

        ( Done value2, Request ( urls1, lookupFn1 ) ) ->
            Request
                ( urls1
                , \appType rawResponses ->
                    lookupFn1 appType rawResponses
                        |> Result.map
                            (\( dict1, value1 ) ->
                                ( dict1, map2 fn (Done value2) value1 )
                            )
                )

        ( Done value1, Done value2 ) ->
            fn value1 value2 |> Done


{-| Takes two dicts representing responses, some of which have been reduced, and picks the shorter of the two.
This is assuming that there are no duplicate URLs, so it can safely choose between either a raw or a reduced response.
It would not work correctly if it chose between two responses that were reduced with different `Json.Decode.Exploration.Decoder`s.
-}
combineReducedDicts : Dict String String -> Dict String String -> Dict String String
combineReducedDicts dict1 dict2 =
    (Dict.toList dict1 ++ Dict.toList dict2)
        |> Dict.Extra.fromListDedupe
            (\response1 response2 ->
                if String.length response1 < String.length response2 then
                    response1

                else
                    response2
            )


lookup : ApplicationType -> DataSource value -> RequestsAndPending -> Result Pages.StaticHttpRequest.Error ( Dict String String, value )
lookup =
    lookupHelp Dict.empty


lookupHelp : Dict String String -> ApplicationType -> DataSource value -> RequestsAndPending -> Result Pages.StaticHttpRequest.Error ( Dict String String, value )
lookupHelp strippedSoFar appType requestInfo rawResponses =
    case requestInfo of
        Request ( urls, lookupFn ) ->
            lookupFn appType rawResponses
                |> Result.andThen
                    (\( strippedResponses, nextRequest ) ->
                        lookupHelp (Dict.union strippedResponses strippedSoFar)
                            appType
                            (addUrls urls nextRequest)
                            rawResponses
                    )

        Done value ->
            Ok ( strippedSoFar, value )


addUrls : List (Pages.Secrets.Value HashRequest.Request) -> DataSource value -> DataSource value
addUrls urlsToAdd requestInfo =
    case requestInfo of
        Request ( initialUrls, function ) ->
            Request ( initialUrls ++ urlsToAdd, function )

        Done value ->
            Done value


{-| The full details to perform a StaticHttp request.
-}
type alias RequestDetails =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body
    }


lookupUrls : DataSource value -> List (Pages.Secrets.Value RequestDetails)
lookupUrls requestInfo =
    case requestInfo of
        Request ( urls, _ ) ->
            urls

        Done _ ->
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
    Request
        ( lookupUrls requestInfo
        , \appType rawResponses ->
            lookup appType
                requestInfo
                rawResponses
                |> (\result ->
                        case result of
                            Err error ->
                                Err error

                            Ok ( strippedResponses, value ) ->
                                ( strippedResponses, fn value ) |> Ok
                   )
        )


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
    Request
        ( []
        , \_ _ ->
            Ok ( Dict.empty, Done value )
        )


{-| Stop the StaticHttp chain with the given error message. If you reach a `fail` in your request,
you will get a build error. Or in the dev server, you will see the error message in an overlay in your browser (and in
the terminal).
-}
fail : String -> DataSource a
fail errorMessage =
    Request
        ( []
        , \_ _ ->
            Err (Pages.StaticHttpRequest.UserCalledStaticHttpFail errorMessage)
        )


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
