module BackendTask exposing
    ( BackendTask
    , map, succeed, fail
    , fromResult
    , andThen, resolve, combine
    , andMap
    , map2, map3, map4, map5, map6, map7, map8, map9
    , allowFatal, mapError, onError, toResult
    , do, doEach, sequence, failIf
    , inDir, quiet, withEnv
    )

{-| In an `elm-pages` app, each Route Module can define a value `data` which is a `BackendTask` that will be resolved **before** `init` is called. That means it is also available
when the page's HTML is pre-rendered during the build step. You can also access the resolved data in `head` to use it for the page's SEO meta tags.

A `BackendTask` lets you pull in data from:

  - Local files ([`BackendTask.File`](BackendTask-File))
  - HTTP requests ([`BackendTask.Http`](BackendTask-Http))
  - Globs, i.e. listing out local files based on a pattern like `content/*.txt` ([`BackendTask.Glob`](BackendTask-Glob))
  - Ports, i.e. getting JSON data from running custom NodeJS, similar to a port in a vanilla Elm app except run at build-time in NodeJS, rather than at run-time in the browser ([`BackendTask.Custom`](BackendTask-Custom))
  - Hardcoded data (`BackendTask.succeed "Hello!"`)
  - Or any combination of the above, using `BackendTask.map2`, `BackendTask.andThen`, or other combining/continuing helpers from this module


## BackendTask's vs. Effect's/Cmd's

BackendTask's are always resolved before the page is rendered and sent to the browser. A BackendTask is never executed
in the Browser. Instead, the resolved data from the BackendTask is passed down to the Browser - it has been resolved
before any client-side JavaScript ever executes. In the case of a pre-rendered route, this is during the CLI build phase,
and for server-rendered routes its BackendTask is resolved on the server.

Effect's/Cmd's are never executed on the CLI or server, they are only executed in the Browser. The data from a Route Module's
`init` function is used to render the initial HTML on the server or build step, but the Effect isn't executed and `update` is never called
before the page is hydrated in the Browser. This gives a deterministic mental model of what the first render will look like,
and a nicely typed way to define the initial `Data` you have to render your initial view.

Because `elm-pages` hydrates into a full Elm single-page app, it does need the data in order to initialize the Elm app.
So why not just get the data the old-fashioned way, with `elm/http`, for example?

A few reasons:

1.  BackendTask's allow you to pull in data that you wouldn't normally be able to access from an Elm app, like local files, or listings of files in a folder. Not only that, but the dev server knows to automatically hot reload the data when the files it depends on change, so you can edit the files you used in your BackendTask and see the page hot reload as you save!
2.  You can pre-render HTML for your pages, including the SEO meta tags, with all that rich, well-typed Elm data available! That's something you can't accomplish with a vanilla Elm app, and it's one of the main use cases for elm-pages.
3.  Because `elm-pages` has a build step, you know that your `BackendTask.Http` requests succeeded, your decoders succeeded, your custom BackendTask validations succeeded, and everything went smoothly. If something went wrong, you get a build failure and can deal with the issues before the site goes live. That means your users won't see those errors, and as a developer you don't need to handle those error cases in your code! Think of it as "parse, don't validate", but for your entire build. In the case of server-rendered routes, a BackendTask failure will render a 500 page, so more care needs to be taken to make sure all common errors are handled properly, but the tradeoff is that you can use BackendTask's to pull in highly dynamic data and even render user-specific pages.
4.  For static routes, you don't have to worry about an API being down, or hitting it repeatedly. You can build in data and it will end up as optimized binary-encoded data served up with all the other assets of your site. If your CDN (static site host) is down, then the rest of your site is probably down anyway. If your site host is up, then so is all of your `BackendTask` data. Also, it will be served up extremely quickly without needing to wait for any database queries to be performed, `andThen` requests to be resolved, etc., because all of that work and waiting was done at build-time!


## Mental Model

You can think of a BackendTask as a declarative (not imperative) definition of data. It represents where to get the data from, and how to transform it (map, combine with other BackendTasks, etc.).


## How do I actually use a BackendTask?

This is very similar to Cmd's in Elm. You don't perform a Cmd just by running that code, as you might in a language like JavaScript. Instead, a Cmd _will not do anything_ unless you pass it to The Elm Architecture to have it perform it for you.
You pass a Cmd to The Elm Architecture by returning it in `init` or `update`. So actually a `Cmd` is just data describing a side-effect that the Elm runtime can perform, and how to build a `Msg` once it's done.

`BackendTask`'s are very similar. A `BackendTask` doesn't do anything just by "running" it. Just like a `Cmd`, it's only data that describes a side-effect to perform. Specifically, it describes a side-effect that the _elm-pages runtime_ can perform.
There are a few places where we can pass a `BackendTask` to the `elm-pages` runtime so it can perform it. Most commonly, you give a field called `data` in your Route Module's definition. Instead of giving a `Msg` when the side-effects are complete,
the page will render once all of the side-effects have run and all the data is resolved. `elm-pages` makes the resolved data available your Route Module's `init`, `view`, `update`, and `head` functions, similar to how a regular Elm app passes `Msg`'s in
to `update`.

Any place in your `elm-pages` app where the framework lets you pass in a value of type `BackendTask` is a place where you can give `elm-pages` a BackendTask to perform (for example, `Site.head` where you define global head tags for your site).


## Basics

@docs BackendTask

@docs map, succeed, fail

@docs fromResult


## Chaining Requests

@docs andThen, resolve, combine

@docs andMap

@docs map2, map3, map4, map5, map6, map7, map8, map9


## FatalError Handling

@docs allowFatal, mapError, onError, toResult


## Scripting

@docs do, doEach, sequence, failIf


## BackendTask Context

You can set the following context for a `BackendTask`:

  - `inDir` - Set the working directory
  - `quiet` - Silence the output
  - `withEnv` - Set an environment variable

It's important to understand that a `BackendTask` does not run until it is passed to the `elm-pages` runtime (it is _not_ run as soon as it is defined,
like you may be familiar with in other languages like JavaScript). So you can use these functions to set the context
of a `BackendTask` at any point before you pass it to and it will be applied when the `BackendTask` is run.

@docs inDir, quiet, withEnv

-}

import Dict
import FatalError exposing (FatalError)
import Json.Encode
import List.Chunks
import Pages.StaticHttpRequest exposing (RawRequest(..))


{-| A BackendTask represents data that will be gathered at build time. Multiple `BackendTask`s can be combined together using the `mapN` functions,
very similar to how you can manipulate values with Json Decoders in Elm.
-}
type alias BackendTask error value =
    RawRequest error value


{-| Transform a request into an arbitrary value. The same underlying task will be performed,
but mapping allows you to change the resulting values by applying functions to the results.

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode exposing (Decoder)

    starsMessage =
        BackendTask.Http.getJson
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.field "stargazers_count" Decode.int)
            |> BackendTask.map
                (\stars -> "⭐️ " ++ String.fromInt stars)

-}
map : (a -> b) -> BackendTask error a -> BackendTask error b
map fn requestInfo =
    case requestInfo of
        ApiRoute value ->
            ApiRoute (Result.map fn value)

        Request urls lookupFn ->
            Request
                urls
                (mapLookupFn fn lookupFn)


{-| `inDir` sets the working directory for a `BackendTask`. The working directory of a `BackendTask` will be used to resolve relative paths
and is relevant for the following types of `BackendTask`s:

  - Reading files ([`BackendTask.File`](BackendTask-File))
  - Running glob patterns ([`BackendTask.Glob`](BackendTask-Glob))
  - Executing shell commands ([`BackendTask.Stream.command`](BackendTask-Stream#command)) and [`Pages.Script.sh`](Pages-Script#command)

See the BackendTask Context section for more about how setting context works.

For example, these two values will produce the same result:

    import BackendTask.Glob as Glob

    example1 : BackendTask error (List String)
    example1 =
        Glob.fromString "src/**/*.elm"

    example2 : BackendTask error (List String)
    example2 =
        BackendTask.inDir "src" (Glob.fromString "**/*.elm")

You can also nest the working directory by using `inDir` multiple times:

    import BackendTask.Glob as Glob

    example3 : BackendTask error (List String)
    example3 =
        BackendTask.map2
            (\routeModules specialModules ->
                { routeModules = routeModules
                , specialModules = specialModules
                }
            )
            (BackendTask.inDir "Route" (Glob.fromString "**/*.elm"))
            (Glob.fromString "*.elm")
            |> BackendTask.inDir "app"

The above example will list out files from `app/Route/**/*.elm` and `app/*.elm` because `inDir "app"` is applied to the `BackendTask.map2` which combines together both of the Glob tasks.

`inDir` supports absolute paths. In this example, we apply a relative path on top of an absolute path, so the relative path will be resolved relative to the absolute path.

    import BackendTask.Glob as Glob

    example3 : BackendTask error (List String)
    example3 =
        BackendTask.map2
            (\routeModules specialModules ->
                { routeModules = routeModules
                , specialModules = specialModules
                }
            )
            -- same as `Glob.fromString "/projects/my-elm-pages-blog/app/Route/**/*.elm"`
            (BackendTask.inDir "Route" (Glob.fromString "**/*.elm"))
            (Glob.fromString "*.elm")
            |> BackendTask.inDir "/projects/my-elm-pages-blog/app"

You can also use `BackendTask.inDir ".."` to go up a directory, or \`BackendTask.inDir "../.." to go up two directories, etc.

Use of trailing slashes is optional and does not change the behavior of `inDir`. Leading slashes distinguish between
absolute and relative paths, so `BackendTask.inDir "./src"` is exactly the same as `BackendTask.inDir "src"`, etc.

Each level of nesting with `inDir` will resolve using [NodeJS's `path.resolve`](https://nodejs.org/api/path.html#pathresolvepaths).

-}
inDir : String -> BackendTask error value -> BackendTask error value
inDir dir backendTask =
    -- elm-review: known-unoptimized-recursion
    -- TODO try to find a way to optimize tail-call recursion here
    case backendTask of
        ApiRoute _ ->
            backendTask

        Request urls lookupFn ->
            Request
                (urls
                    |> List.map (\req -> { req | dir = dir :: req.dir })
                )
                (\a b -> lookupFn a b |> inDir dir)


{-| Sets the verbosity level to `quiet` in the context of the given `BackendTask` (including all nested `BackendTask`s and continuations within it).

This will turn off performance timing logs. It will also prevent shell commands from printing their output to the console when they are run
(see [`BackendTask.Stream.command`](BackendTask-Stream#command)).

-}
quiet : BackendTask error value -> BackendTask error value
quiet backendTask =
    -- elm-review: known-unoptimized-recursion
    -- TODO try to find a way to optimize tail-call recursion here
    case backendTask of
        ApiRoute _ ->
            backendTask

        Request urls lookupFn ->
            Request
                (urls
                    |> List.map (\req -> { req | quiet = True })
                )
                (\a b -> lookupFn a b |> quiet)


{-| -}
withEnv : String -> String -> BackendTask error value -> BackendTask error value
withEnv key value backendTask =
    -- elm-review: known-unoptimized-recursion
    -- TODO try to find a way to optimize tail-call recursion here
    case backendTask of
        ApiRoute _ ->
            backendTask

        Request urls lookupFn ->
            Request
                (urls
                    |> List.map (\req -> { req | env = req.env |> Dict.insert key value })
                )
                (\a b -> lookupFn a b |> withEnv key value)


mapLookupFn : (a -> b) -> (d -> c -> BackendTask error a) -> d -> c -> BackendTask error b
mapLookupFn fn lookupFn maybeMock requests =
    map fn (lookupFn maybeMock requests)


{-| Helper to remove an inner layer of Request wrapping.
-}
resolve : BackendTask error (List (BackendTask error value)) -> BackendTask error (List value)
resolve =
    andThen combine


{-| Turn a list of `BackendTask`s into a single one.

    import BackendTask
    import FatalError exposing (FatalError)
    import Json.Decode as Decode exposing (Decoder)

    type alias Pokemon =
        { name : String
        , sprite : String
        }

    pokemonDetailRequest : BackendTask FatalError (List Pokemon)
    pokemonDetailRequest =
        BackendTask.Http.getJson
            "https://pokeapi.co/api/v2/pokemon/?limit=3"
            (Decode.field "results"
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.field "name" Decode.string)
                        (Decode.field "url" Decode.string)
                        |> Decode.map
                            (\( name, url ) ->
                                BackendTask.Http.getJson url
                                    (Decode.at
                                        [ "sprites", "front_default" ]
                                        Decode.string
                                        |> Decode.map (Pokemon name)
                                    )
                            )
                    )
                )
            )
            |> BackendTask.andThen BackendTask.combine
            |> BackendTask.allowFatal

-}
combine : List (BackendTask error value) -> BackendTask error (List value)
combine items =
    items
        |> List.Chunks.chunk 100
        |> List.map combineHelp
        |> List.Chunks.chunk 100
        |> List.map combineHelp
        |> List.Chunks.chunk 100
        |> List.map combineHelp
        |> combineHelp
        |> map (List.concat >> List.concat >> List.concat)


{-| `combineHelp` on its own will overflow the stack with larger lists of tasks

dividing the tasks into smaller nested chunks and recombining makes `combine` stack safe

There's probably a way of doing this without the Lists but it's a neat trick to safely combine lots of tasks!

-}
combineHelp : List (BackendTask error value) -> BackendTask error (List value)
combineHelp items =
    List.foldl (map2 (::)) (succeed []) items |> map List.reverse


{-| Perform a List of `BackendTask`s with no output, one-by-one sequentially.

Same as [`sequence`](#sequence), except it ignores the resulting value of each `BackendTask`.

-}
doEach : List (BackendTask error ()) -> BackendTask error ()
doEach items =
    items
        |> sequenceHelp
        |> map (\_ -> ())


{-| Ignore the resulting value of the BackendTask.
-}
do : BackendTask error value -> BackendTask error ()
do backendTask =
    backendTask
        |> map (\_ -> ())


{-| Perform a List of `BackendTask`s one-by-one sequentially. [`combine`](#combine) will perform them all in parallel, which is
typically a better default when you aren't sure which you want.

Same as [`doEach`](#doEach), except it ignores the resulting value of each `BackendTask`.

-}
sequence : List (BackendTask error value) -> BackendTask error (List value)
sequence items =
    items
        |> sequenceHelp


sequenceHelp : List (BackendTask error value) -> BackendTask error (List value)
sequenceHelp items =
    List.foldl
        (\item accumulator ->
            accumulator
                |> andThen
                    (\accValue ->
                        item
                            |> map (\itemValue -> itemValue :: accValue)
                    )
        )
        (succeed [])
        items
        |> map List.reverse


{-| Like map, but it takes in two `BackendTask`s.

    import BackendTask exposing (BackendTask)
    import BackendTask.Env as Env
    import BackendTask.Http
    import FatalError exposing (FatalError)
    import Json.Decode as Decode

    type alias Data =
        { pokemon : List String, envValue : Maybe String }

    data : BackendTask FatalError Data
    data =
        BackendTask.map2 Data
            (BackendTask.Http.getJson
                "https://pokeapi.co/api/v2/pokemon/?limit=100&offset=0"
                (Decode.field "results"
                    (Decode.list (Decode.field "name" Decode.string))
                )
                |> BackendTask.allowFatal
            )
            (Env.get "HELLO")

-}
map2 : (a -> b -> c) -> BackendTask error a -> BackendTask error b -> BackendTask error c
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


{-| Build off of the response from a previous `BackendTask` request to build a follow-up request. You can use the data
from the previous response to build up the URL, headers, etc. that you send to the subsequent request.

    import BackendTask
    import FatalError exposing (FatalError)
    import Json.Decode as Decode exposing (Decoder)

    licenseData : BackendTask FatalError String
    licenseData =
        BackendTask.Http.getJson
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.at [ "license", "url" ] Decode.string)
            |> BackendTask.andThen
                (\licenseUrl ->
                    BackendTask.Http.getJson licenseUrl (Decode.field "description" Decode.string)
                )
            |> BackendTask.allowFatal

-}
andThen : (a -> BackendTask error b) -> BackendTask error a -> BackendTask error b
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
                andThen fn (lookupFn Nothing (Json.Encode.object []))

            else
                Request urls
                    (\maybeMockResolver responses ->
                        lookupFn maybeMockResolver responses
                            |> andThen fn
                    )


{-| -}
onError : (error -> BackendTask mappedError value) -> BackendTask error value -> BackendTask mappedError value
onError fromError backendTask =
    -- elm-review: known-unoptimized-recursion
    case backendTask of
        ApiRoute a ->
            case a of
                Ok okA ->
                    succeed okA

                Err errA ->
                    fromError errA

        Request urls lookupFn ->
            if List.isEmpty urls then
                onError fromError (lookupFn Nothing (Json.Encode.object []))

            else
                Request urls
                    (\maybeMockResolver responses ->
                        lookupFn maybeMockResolver responses
                            |> onError fromError
                    )


{-| A helper for combining `BackendTask`s in pipelines.
-}
andMap : BackendTask error a -> BackendTask error (a -> b) -> BackendTask error b
andMap =
    map2 (|>)


{-| This is useful for prototyping with some hardcoded data, or for having a view that doesn't have any BackendTask data.

    import BackendTask exposing (BackendTask)

    type alias RouteParams =
        { name : String }

    pages : BackendTask error (List RouteParams)
    pages =
        BackendTask.succeed [ { name = "elm-pages" } ]

-}
succeed : a -> BackendTask error a
succeed value =
    ApiRoute (Ok value)


{-| -}
fail : error -> BackendTask error a
fail error =
    ApiRoute (Err error)


{-| Turn `Ok` into `BackendTask.succeed` and `Err` into `BackendTask.fail`.
-}
fromResult : Result error value -> BackendTask error value
fromResult result =
    case result of
        Ok okValue ->
            succeed okValue

        Err error ->
            fail error


{-| -}
mapError : (error -> errorMapped) -> BackendTask error value -> BackendTask errorMapped value
mapError mapFn requestInfo =
    case requestInfo of
        ApiRoute value ->
            ApiRoute (Result.mapError mapFn value)

        Request urls lookupFn ->
            Request
                urls
                (mapLookupFnError mapFn lookupFn)


mapLookupFnError : (error -> errorMapped) -> (d -> c -> BackendTask error a) -> d -> c -> BackendTask errorMapped a
mapLookupFnError fn lookupFn maybeMock requests =
    mapError fn (lookupFn maybeMock requests)


{-| -}
map3 :
    (value1 -> value2 -> value3 -> valueCombined)
    -> BackendTask error value1
    -> BackendTask error value2
    -> BackendTask error value3
    -> BackendTask error valueCombined
map3 combineFn request1 request2 request3 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3


{-| -}
map4 :
    (value1 -> value2 -> value3 -> value4 -> valueCombined)
    -> BackendTask error value1
    -> BackendTask error value2
    -> BackendTask error value3
    -> BackendTask error value4
    -> BackendTask error valueCombined
map4 combineFn request1 request2 request3 request4 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4


{-| -}
map5 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> valueCombined)
    -> BackendTask error value1
    -> BackendTask error value2
    -> BackendTask error value3
    -> BackendTask error value4
    -> BackendTask error value5
    -> BackendTask error valueCombined
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
    -> BackendTask error value1
    -> BackendTask error value2
    -> BackendTask error value3
    -> BackendTask error value4
    -> BackendTask error value5
    -> BackendTask error value6
    -> BackendTask error valueCombined
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
    -> BackendTask error value1
    -> BackendTask error value2
    -> BackendTask error value3
    -> BackendTask error value4
    -> BackendTask error value5
    -> BackendTask error value6
    -> BackendTask error value7
    -> BackendTask error valueCombined
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
    -> BackendTask error value1
    -> BackendTask error value2
    -> BackendTask error value3
    -> BackendTask error value4
    -> BackendTask error value5
    -> BackendTask error value6
    -> BackendTask error value7
    -> BackendTask error value8
    -> BackendTask error valueCombined
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
    -> BackendTask error value1
    -> BackendTask error value2
    -> BackendTask error value3
    -> BackendTask error value4
    -> BackendTask error value5
    -> BackendTask error value6
    -> BackendTask error value7
    -> BackendTask error value8
    -> BackendTask error value9
    -> BackendTask error valueCombined
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


{-| Ignore any recoverable error data and propagate the `FatalError`. Similar to a `Cmd` in The Elm Architecture,
a `FatalError` will not do anything except if it is returned at the top-level of your application. Read more
in the [`FatalError` docs](FatalError).
-}
allowFatal : BackendTask { error | fatal : FatalError } data -> BackendTask FatalError data
allowFatal backendTask =
    mapError .fatal backendTask


{-| -}
toResult : BackendTask error data -> BackendTask noError (Result error data)
toResult backendTask =
    backendTask
        |> andThen (Ok >> succeed)
        |> onError (Err >> succeed)


{-| If the condition is true, fail with the given `FatalError`. Otherwise, succeed with `()`.
-}
failIf : Bool -> FatalError -> BackendTask FatalError ()
failIf condition fatalError =
    if condition then
        fail fatalError

    else
        succeed ()
