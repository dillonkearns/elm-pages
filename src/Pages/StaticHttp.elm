module Pages.StaticHttp exposing
    ( Request, RequestDetails
    , get, request
    , map, succeed
    , Body, emptyBody, stringBody
    , andThen, resolve, combine
    , map2, map3, map4, map5, map6, map7, map8, map9
    , unoptimizedRequest
    )

{-| StaticHttp requests are an alternative to doing Elm HTTP requests the traditional way using the `elm/http` package.

The key differences are:

  - `StaticHttp.Request`s are performed once at build time (`Http.Request`s are performed at runtime, at whenever point you perform them)
  - `StaticHttp.Request`s strip out unused JSON data from the data your decoder doesn't touch to minimize the JSON payload
  - `StaticHttp.Request`s can use [`Pages.Secrets`](Pages.Secrets) to securely use credentials from your environemnt variables which are completely masked in the production assets.
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

@docs Request, RequestDetails
@docs get, request
@docs map, succeed


## Building a StaticHttp Request Body

The way you build a body is analagous to the `elm/http` package. Currently, only `emptyBody` and
`stringBody` are supported. If you have a use case that calls for a different body type, please open a Github issue
and describe your use case!

@docs Body, emptyBody, stringBody


## Chaining Requests

@docs andThen, resolve, combine

@docs map2, map3, map4, map5, map6, map7, map8, map9


## Unoptimized Requests

Warning - use these at your own risk! It's highly recommended that you use the other request functions that make use of
`zwilias/json-decode-exploration` in order to allow you to reduce down your JSON to only the values that are used by
your decoders. This can significantly reduce download sizes for your StaticHttp requests.

@docs unoptimizedRequest

-}

import Dict exposing (Dict)
import Dict.Extra
import Json.Decode
import Json.Decode.Exploration as Decode exposing (Decoder)
import Json.Encode as Encode
import Pages.Internal.StaticHttpBody as Body
import Pages.Secrets
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (Request(..))
import Secrets


{-| Build an empty body for a StaticHttp request. See [elm/http's `Http.emptyBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#emptyBody).
-}
emptyBody : Body
emptyBody =
    Body.EmptyBody


{-| Builds a string body for a StaticHttp request. See [elm/http's `Http.stringBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#stringBody).
-}
stringBody : String -> Body
stringBody content =
    Body.StringBody content


{-| Builds a JSON body for a StaticHttp request. See [elm/http's `Http.jsonBody`](https://package.elm-lang.org/packages/elm/http/latest/Http#jsonBody).
-}
jsonBody : Encode.Value -> Body
jsonBody content =
    Body.JsonBody content


{-| A body for a StaticHttp request.
-}
type alias Body =
    Body.Body


{-| A Request that will be made a build time. Multiple `StaticHttp.Request`s can be combined together using the `mapN` functions,
very similar to how you can manipulate values with Json Decoders in Elm.
-}
type alias Request value =
    Pages.StaticHttpRequest.Request value


{-| Transform a request into an arbitrary value. The same underlying HTTP requests will be performed during the build
step, but mapping allows you to change the resulting values by applying functions to the results.

A common use for this is to map your data into your elm-pages view:

    import Json.Decode as Decode exposing (Decoder)
    import Pages.StaticHttp as StaticHttp

    view =
        StaticHttp.get "https://api.github.com/repos/dillonkearns/elm-pages"
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
map : (a -> b) -> Request a -> Request b
map fn requestInfo =
    case requestInfo of
        Request ( urls, lookupFn ) ->
            Request
                ( urls
                , \rawResponses ->
                    lookupFn rawResponses
                        |> Result.map (\( partiallyStripped, nextRequest ) -> ( partiallyStripped, map fn nextRequest ))
                )

        Done value ->
            fn value |> Done


{-| Helper to remove an inner layer of Request wrapping.
-}
resolve : Request (List (Request value)) -> Request (List value)
resolve topRequest =
    topRequest
        |> andThen
            (\continuationRequests -> combine continuationRequests)


{-| Turn a list of `StaticHttp.Request`s into a single one.

    import Json.Decode as Decode exposing (Decoder)
    import Pages.StaticHttp as StaticHttp

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
combine : List (Request value) -> Request (List value)
combine requests =
    requests
        |> List.foldl (map2 (::)) (succeed [])


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
            (get "https://api.github.com/repos/dillonkearns/elm-pages"
                (Decode.field "stargazers_count" Decode.int)
            )
            (get "https://api.github.com/repos/dillonkearns/elm-markdown"
                (Decode.field "stargazers_count" Decode.int)
            )

-}
map2 : (a -> b -> c) -> Request a -> Request b -> Request c
map2 fn request1 request2 =
    case ( request1, request2 ) of
        ( Request ( urls1, lookupFn1 ), Request ( urls2, lookupFn2 ) ) ->
            let
                value : Dict String String -> Result Pages.StaticHttpRequest.Error ( Dict String String, Request c )
                value rawResponses =
                    let
                        value1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.second

                        value2 =
                            lookupFn2 rawResponses
                                |> Result.map Tuple.second

                        dict1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.first
                                |> Result.withDefault Dict.empty

                        dict2 =
                            lookupFn2 rawResponses
                                |> Result.map Tuple.first
                                |> Result.withDefault Dict.empty
                    in
                    Result.map2
                        (\thing1 thing2 ->
                            ( combineReducedDicts dict1 dict2, map2 fn thing1 thing2 )
                        )
                        value1
                        value2
            in
            Request
                ( urls1 ++ urls2
                , value
                )

        ( Request ( urls1, lookupFn1 ), Done value2 ) ->
            Request
                ( urls1
                , \rawResponses ->
                    let
                        value1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.second

                        dict1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.first
                                |> Result.withDefault Dict.empty
                    in
                    Result.map2
                        (\thing1 thing2 ->
                            ( dict1, map2 fn thing1 thing2 )
                        )
                        value1
                        (Ok (Done value2))
                )

        ( Done value2, Request ( urls1, lookupFn1 ) ) ->
            Request
                ( urls1
                , \rawResponses ->
                    let
                        value1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.second

                        dict1 =
                            lookupFn1 rawResponses
                                |> Result.map Tuple.first
                                |> Result.withDefault Dict.empty
                    in
                    Result.map2
                        (\thing1 thing2 ->
                            ( dict1, map2 fn thing1 thing2 )
                        )
                        (Ok (Done value2))
                        value1
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


lookup : Pages.StaticHttpRequest.Request value -> Dict String String -> Result Pages.StaticHttpRequest.Error ( Dict String String, value )
lookup requestInfo rawResponses =
    case requestInfo of
        Request ( urls, lookupFn ) ->
            lookupFn rawResponses
                |> Result.andThen
                    (\( strippedResponses, nextRequest ) ->
                        lookup
                            (addUrls urls nextRequest)
                            strippedResponses
                    )

        Done value ->
            Ok ( rawResponses, value )


addUrls : List (Pages.Secrets.Value HashRequest.Request) -> Pages.StaticHttpRequest.Request value -> Pages.StaticHttpRequest.Request value
addUrls urlsToAdd requestInfo =
    case requestInfo of
        Request ( initialUrls, function ) ->
            Request ( initialUrls ++ urlsToAdd, function )

        Done value ->
            Done value


lookupUrls : Pages.StaticHttpRequest.Request value -> List (Pages.Secrets.Value RequestDetails)
lookupUrls requestInfo =
    case requestInfo of
        Request ( urls, lookupFn ) ->
            urls

        Done value ->
            []


{-| Build off of the response from a previous `StaticHttp` request to build a follow-up request. You can use the data
from the previous response to build up the URL, headers, etc. that you send to the subsequent request.

    import Json.Decode as Decode exposing (Decoder)
    import Pages.StaticHttp as StaticHttp

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
andThen : (a -> Request b) -> Request a -> Request b
andThen fn requestInfo =
    Request
        ( lookupUrls requestInfo
        , \rawResponses ->
            lookup
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

    import Pages.StaticHttp as StaticHttp

    view :
        List ( PagePath Pages.PathKey, Metadata )
        ->
            { path : PagePath Pages.PathKey
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
succeed : a -> Request a
succeed value =
    Request
        ( []
        , \rawResponses ->
            Ok ( rawResponses, Done value )
        )


{-| A simplified helper around [`StaticHttp.request`](#request), which builds up a StaticHttp GET request.

    import Json.Decode as Decode exposing (Decoder)
    import Pages.StaticHttp as StaticHttp

    getRequest : StaticHttp.Request Int
    getRequest =
        StaticHttp.get "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.field "stargazers_count" Decode.int)

-}
get :
    Pages.Secrets.Value String
    -> Decoder a
    -> Request a
get url decoder =
    request
        (url
            |> Secrets.map
                (\okUrl ->
                    { url = okUrl
                    , method = "GET"
                    , headers = []
                    , body = emptyBody
                    }
                )
        )
        decoder


{-| The full details to perform a StaticHttp request.
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


{-| Build a `StaticHttp` request (analagous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `StaticHttp` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [StaticHttp.get](#get).
-}
request :
    Pages.Secrets.Value RequestDetails
    -> Decoder a
    -> Request a
request urlWithSecrets decoder =
    Request
        ( [ urlWithSecrets ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get (Secrets.maskedLookup urlWithSecrets |> HashRequest.hash)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                Ok
                                    ( rawResponseDict
                                      --                                        |> Dict.update url (\maybeValue -> Just """{"fake": 123}""")
                                    , rawResponse
                                    )

                            Nothing ->
                                Secrets.maskedLookup urlWithSecrets
                                    |> requestToString
                                    |> Pages.StaticHttpRequest.MissingHttpResponse
                                    |> Err
                   )
                |> Result.andThen
                    (\( strippedResponses, rawResponse ) ->
                        let
                            reduced =
                                Decode.stripString decoder rawResponse
                                    |> Result.withDefault "TODO"
                        in
                        rawResponse
                            |> Decode.decodeString decoder
                            --                                                        |> Result.mapError Json.Decode.Exploration.errorsToString
                            |> (\decodeResult ->
                                    case decodeResult of
                                        Decode.BadJson ->
                                            Pages.StaticHttpRequest.DecoderError "Payload sent back invalid JSON" |> Err

                                        Decode.Errors errors ->
                                            errors
                                                |> Decode.errorsToString
                                                |> Pages.StaticHttpRequest.DecoderError
                                                |> Err

                                        Decode.WithWarnings warnings a ->
                                            --                                            Pages.StaticHttpRequest.DecoderError "" |> Err
                                            Ok a

                                        Decode.Success a ->
                                            Ok a
                               )
                            --                            |> Result.mapError Pages.StaticHttpRequest.DecoderError
                            |> Result.map Done
                            |> Result.map
                                (\finalRequest ->
                                    ( strippedResponses
                                        |> Dict.insert
                                            (Secrets.maskedLookup urlWithSecrets |> HashRequest.hash)
                                            reduced
                                    , finalRequest
                                    )
                                )
                    )
        )


{-| Build a `StaticHttp` request (analagous to [Http.request](https://package.elm-lang.org/packages/elm/http/latest/Http#request)).
This function takes in all the details to build a `StaticHttp` request, but you can build your own simplified helper functions
with this as a low-level detail, or you can use functions like [StaticHttp.get](#get).
-}
unoptimizedRequest :
    Pages.Secrets.Value RequestDetails
    -> Json.Decode.Decoder a
    -> Request a
unoptimizedRequest urlWithSecrets decoder =
    Request
        ( [ urlWithSecrets ]
        , \rawResponseDict ->
            rawResponseDict
                |> Dict.get (Secrets.maskedLookup urlWithSecrets |> HashRequest.hash)
                |> (\maybeResponse ->
                        case maybeResponse of
                            Just rawResponse ->
                                Ok
                                    ( rawResponseDict
                                      --                                        |> Dict.update url (\maybeValue -> Just """{"fake": 123}""")
                                    , rawResponse
                                    )

                            Nothing ->
                                Secrets.maskedLookup urlWithSecrets
                                    |> requestToString
                                    |> Pages.StaticHttpRequest.MissingHttpResponse
                                    |> Err
                   )
                |> Result.andThen
                    (\( strippedResponses, rawResponse ) ->
                        rawResponse
                            |> Json.Decode.decodeString decoder
                            --                                                        |> Result.mapError Json.Decode.Exploration.errorsToString
                            |> (\decodeResult ->
                                    case decodeResult of
                                        Err error ->
                                            Pages.StaticHttpRequest.DecoderError "Payload sent back invalid JSON" |> Err

                                        Ok a ->
                                            Ok a
                               )
                            |> Result.map Done
                            |> Result.map
                                (\finalRequest ->
                                    ( strippedResponses
                                        |> Dict.insert
                                            (Secrets.maskedLookup urlWithSecrets |> HashRequest.hash)
                                            rawResponse
                                    , finalRequest
                                    )
                                )
                    )
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


{-| -}
map4 :
    (value1 -> value2 -> value3 -> value4 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request valueCombined
map4 combineFn request1 request2 request3 request4 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4


{-| -}
map5 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> valueCombined)
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request valueCombined
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
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request value6
    -> Request valueCombined
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
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request value6
    -> Request value7
    -> Request valueCombined
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
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request value6
    -> Request value7
    -> Request value8
    -> Request valueCombined
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
    -> Request value1
    -> Request value2
    -> Request value3
    -> Request value4
    -> Request value5
    -> Request value6
    -> Request value7
    -> Request value8
    -> Request value9
    -> Request valueCombined
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
