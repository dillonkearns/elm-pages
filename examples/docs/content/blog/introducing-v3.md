---
{
  "author": "Dillon Kearns",
  "title": "Introducing elm-pages v3",
  "description": "While elm-pages v2 was focused on static site generation, elm-pages v3 is a hybrid framework, giving you all the same static site generation features from v2, but with a whole new set of use cases opened up with server-rendered routes.",
  "image": "v1627861555/elm-pages/article-covers/photo-1471107340929-a87cd0f5b5f3_mczjfg.jpg",
  "published": "2023-06-14",
}
---

I'm excited to announce the release of `elm-pages` v3! This has been a real labor of love that I've been working on for over a year. I am truly excited to see what the Elm community builds with it. I believe the new features in v3 open up a lot more use cases, and I hope that it makes it delightful to build full-stack Elm applications!

## Server-rendered routes (full-stack Elm!)

While `elm-pages` v2 was focused on static site generation, `elm-pages` v3 is a hybrid framework, giving you all the same static site generation features from v2, but with a whole new set of use cases opened up with server-rendered routes.

`elm-pages` v3 is focused on making it easy to build full-stack Elm apps. This means that you can use `elm-pages` to build a full-stack Elm app that can render pages on the server, and then hydrate them on the client. Because your data is resolved on the backend before it's sent to the client, you have your fully resolved data before your `view` is rendered, which means no intermediary `Maybe` loading or error states, and no loading spinners. You can resolve data on the server in a low-latency environment close to your data, and then ship the dense, processed data to the client for a rich initial render.

```elm
type alias Data =
    Post


data :
    RouteParams
    -> Request
    -> BackendTask (Response Data ErrorPage)
data routeParams request =
    findPost routeParams.slug
        |> BackendTask.map
            (\maybePost ->
                case maybePost of
                    Just post ->
                        Response.render post

                    Nothing ->
                        Response.errorPage ErrorPage.notFound
            )


type alias Post =
    { slug : String
    , title : String
    , body : List Markdown.Block.Block
    , likes : Int
    , views : Int
    }


findPost : String -> BackendTask FatalError (Maybe Post)
findPost slug =
    BackendTask.Custom.run "findPost"
        (Encode.string slug)
        postDecoder


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared model =
    { title = "My Page"
    , body =
        [ -- we have access to the `Post`, no `Maybe`, no loading spinners!
          postView app.data
        ]
    }


postView : Post -> Html msg
postDecoder : Json.Decode.Decoder Post
```

Using [`BackendTask.Custom.run`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask-Custom#run), we can directly make a database request to find the post with a database query. This will run an async NodeJS function from our definitions in a file called `custom-backend-task.ts`. For example, we might use the NPM package Prisma to make a database query.

```js
// custom-backend-task.ts

import { PrismaClient } from "@prisma/client";
const prisma = new PrismaClient();

// this runs when our Elm code uses `BackendTask.Custom.run "findPost"`
export async function findPost(slug) {
  return await prisma.post.findFirst({
    where: { slug },
  });
}
```

`BackendTask`'s also let us run any markdown parsing and other expensive processing on the backend instead of the user's browser. By doing this work on the server, we can resolve the core data for the page in a single pass, and avoid sending unprocessed data or doing multiple round trips to the server from the client. As a bonus, because we are only running our Markdown parsing from our `data` function (which is only executed on our Backend), this is dead-code eliminated from our client bundle! That means that not only does the execution of running markdown parsing not bog down the user's browser, but it doesn't even need to download the markdown parser code!

Plus, we get the initial page load with a rich intial render, no loading spinners or flashes of blank content. If we architect our app effectively with our data center co-located with our `elm-pages` Backend server, and well-tuned database queries, we can get a very compelling performance story.

Notice also that we have the ability to dynamically render an error page if the post is not found (learn more in the [ErrorPage docs](/docs/error-pages)). This opens up new use cases because we can decide whether to render a 404 page based on the data we get back from our database at request-time (rather than pre-rendering a finite set of pages at build-time). With this workflow, we could even publish a post to our database and have it show up without running a build. `elm-pages` v3 provides error handling abstractions to render routes with your happy path data clean and free of error states and loading spinners, while still letting you bail out of the happy path to present an error page when needed.

`elm-pages` v3 still fully supports static site generation with `RouteBuidler.preRender` (in fact, this blog is an example of that!). But you can choose the right architecture, or even transition in to more flexiblility when you need it with the new suite of hybrid features in v3.

## Server-rendered API Routes

You can also define API routes that are rendered on the server. That means in addition to generating static files like RSS feeds, you can serve dynamic APIs like a dynamic RSS feed that pulls in on-demand data from a database, or even a JSON API.

## Adapters

If you're wondering how the server-side part of an elm-pages app is hosted, take a look at [the adapter docs page](/docs/adapters). There is a built-in adapter for Netlify serverless functions, and there are some community adapters being developed for frameworks like Express. You can define your own for your deployment target of choice.

And if you're wondering how the magic of full-stack routes in elm-pages works overall, check out the docs page on [The elm-pages Architecture](/docs/architecture).

## Goodbye `OptimizedDecoder`s!

This is one of those wonderful cases where it's all upside. In v3, you no longer need to use `OptimizedDecoder`s to ensure that your page loads pull in only the essential data they depend on. Instead, `elm-pages` automatically serializes your `Route` data, only serializing exactly the final data you end up with in your `data` function. Not only that, but the data is serialized in a more compact binary format, giving even better performance. That means instead of using the `Json.Decode` drop-in replacement for your `v2` data with `import OptimizedDecoder`, you can just use vanilla JSON Decoders and you will end up with compact data.

The data that is sent to the client is exactly the type you define in your Route Module's `Data` type. That means you don't need to worry about whether any sensitive intermediary data ended up in the page data. What you see is what you get. You can read about some of the old [caveats of data serialization from v2 for comparison in the docs archive](https://package.elm-lang.org/packages/dillonkearns/elm-pages/9.0.0/DataSource#optimizing-page-data).

## DataSource renamed to BackendTask

To reflect the broader use cases that are supported now with this abstraction in v3 with full-stack server-rendered routes and scripts, we've renamed `DataSource` to `BackendTask`.

In v2, this was a mechanism for pulling in static data to your Routes. In v3, you might want to perform a side-effect using this tool. For example, you could delete an item when a form is submitted.

This means that the semantics have changed. The [v3 `BackendTask.Http` API provides some caching options](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask-Http#caching-options) to explicitly manage cases where you want to perform HTTP GET requests with a local cache. However, if you perform a non-GET request, since it may represent a side-effect (like deleting an entry), the v3 semantics do not cache non-GET requests.

## Explicit errors with `BackendTask FatalError data`

In addition to the name to better reflect the broader use cases that are supported in v3, `BackendTask` also has an explicit type variable for errors now, just like the `elm/core` `Task`.

In v2, a `DataSource` could cause a build failure without that being reflected in its type. This was reasonable for static sites because an unexpected build failure is more manageable than an unexpected error at run-time. For example, if an HTTP request fails because an API is down, you probably want the build to fail and don't need to do any sophisticated error handling. With server-rendered routes in v3, I wanted it to be possible to see whether or not a `BackendTask` can fail just by looking at its type, and also to be able to gracefully handle possible error cases.

If you have a `BackendTask Never String`, for example, you know that it will never result in an error.

Here are two different ways you could handle HTTP errors in v3. `handled` will give `Nothing` on failure, and will never result in a `BackendTask` error. `unhandled` yields a `FatalError` if anything goes wrong. The `data` function in your elm-pages Route Modules has type `BackendTask FatalError Data`, and the framework will handle the [`FatalError`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/FatalError) by printing the error message and failing the build for static pre-rendered routes, or by rendering a 500 error page for server-rendered routes.

```elm
handled : BackendTask.BackendTask Never (Maybe Int)
handled =
    BackendTask.Http.getJson
        "https://api.github.com/repos/dillonkearns/elm-pages"
        (Decode.field "stargazers_count" Decode.int)
        |> BackendTask.map Just
        |> BackendTask.onError (\_ -> BackendTask.succeed Nothing)

unhandled : BackendTask FatalError Int
unhandled =
    BackendTask.Http.getJson
        "https://api.github.com/repos/dillonkearns/elm-pages"
        (Decode.field "stargazers_count" Decode.int)
        |> BackendTask.allowFatal

```

## elm-pages Scripts

With the more general-purpose `BackendTask` API, it made sense to provide a way to just run a `BackendTask` directly from the command-line (no HTML view or routing, just execute a task as a script). One of the major goals for `elm-pages` Scripts was to make it as frictionless as possible to execute headless Elm code, and I think we've achieved that. The script is part of an Elm project (a folder with an `elm.json` listing out its dependencies). You can run a script from any directory by passing in the file path, for example `elm-pages run scripts/src/HelloWorld.elm`. It will find the closest `elm.json` based on the file path you pass in.

Here's the `HelloWorld.elm` script:

```elm
module HelloWorld exposing (run)

import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "Hello, World!")
```

I think this is one of the best ways to try out `elm-pages` to get a feel for the `BackendTask` API and what you can do with it, as well as how error handling works in `elm-pages`. Check out [the quick start and intro to elm-pages scripts in the docs](/docs/scripts).

`elm-pages` Scripts also has a `Script.withCliOptions` that lets you parse command-line options using [`dillonkearns/elm-cli-options-parser`](https://package.elm-lang.org/packages/dillonkearns/elm-cli-options-parser/latest/), so you can build full-fledged CLI utilities in pure Elm.

There is also an `elm-pages bundle-script` command for bundling into a single executable JavaScript file (including any NodeJS dependencies).

## Customizable scaffolding scripts with elm-codegen

`elm-pages` v3 introduces a new approach to scaffolding Route Modules that is more customizable. You may have guessed already - the scaffolding commands are actually just `elm-pages` Scripts!

The scaffolding uses the excellent tool [`mdgriffith/elm-codegen`](https://github.com/mdgriffith/elm-codegen) to generate the Route Modules. `elm-codegen` provides a high-level way to write Elm code that generates Elm code. Sounds scary, but it's a lot of fun to use! `elm-pages` [abstracts out the boilerplate around Routes](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Scaffold-Route) [and Forms](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Scaffold-Form), so you can focus on customizing your within the confines of generating a valid Route Module.

With `elm-pages` Scripts-based scaffolding, you have full programmatic control over your scaffolding, and all in pure Elm. You can run arbitrary `BackendTask`s, and customize your scaffolding with command-line options. Here's an example of the scaffolding script [](https://github.com/dillonkearns/elm-pages/blob/5633707ae7c9d6bfc3f920b12df06eb8ea9b1098/examples/end-to-end/script/src/AddRoute.elm). The `elm-pages-starter` repo and the `elm-pages init` project skeleton both come with a `script/src/AddRoute.elm` script that you can customize to your needs.

## Built-in Vite Integration

In v2, there was a philosophy of "bring your own bundler". The web ecosystem had so many different approaches to post-processing - Webpack, Parcel, Rollup, Snowpack. Or just the TypeScript compiler, PostCSS CLI, and other standalone post-processing tools. There wasn't a clear winner, and often tools that choose a bundler like Webpack ended up exposing dangerous configuration options that could interfere with the way the framework bundled the core app.

That all changed when Vite came out with a refreshingly sane approach to bundling. It is conventions-based (no configuration needed for many common tools, for example it will find your TypeScript config file and use that automatically). Plus it is extremely fast, and has a rich ecosystem, and a simple plugin API. So `elm-pages` V3 comes with a built-in Vite integration.

`elm-pages` still does its own processing of the core Elm code in your app so you can't break your app by mistake, and you get your Elm code bundled and optimized for production with zero configuration (it even runs `elm-optimize-level-2` on the production build!). And you get seamless hot data reloading as well - try defining a Route Module with `Data` that pulls in content from a file (`BackendTask.File`) or uses a Glob pattern to list matching files (`BackendTask.Glob`), and you'll see the page hot reload with the latest data as you touch files that your Route Module depends on.

For all of your non-Elm bundling needs, you get the simplicity and power of Vite. You can customize your Vite configuration in the `elm-pages.config.mjs` file ([here's this docs site's Vite configuration](https://github.com/dillonkearns/elm-pages/blob/10e2c14d1e354fed988b7c6832708fc2f52b64d1/examples/docs/elm-pages.config.mjs#L5-L11)).

## Session API

[One of the core foundational principles of this v3 release is "Use the platform"](http://localhost:1234/docs/use-the-platform). `elm-pages` leverages Web standards.

That brings a lot of conveniences for server-rendered routes, like using cookie-based sessions through [the Session API](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Server-Session).

```elm
import Server.Session as Session
import BackendTask exposing (BackendTask)
import Effect
import ErrorPage exposing (ErrorPage)
import FatalError
import Form
import Form.Field
import Form.FieldView
import Form.Handler
import Form.Validation
import Head
import Html.Styled
import Html.Styled.Attributes
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App)
import Server.Request
import Server.Response
import Shared
import View


secrets : BackendTask FatalError (List String)
secrets =
    Env.expect "SESSION_SECRET"
        |> BackendTask.allowFatal
        |> BackendTask.map List.singleton

type alias Data =
    { darkMode : Bool }

data : RouteParams -> Request -> BackendTask (Response Data ErrorPage)
data routeParams request =
    request
        |> Session.withSession
            { name = "mysession"
            , secrets = secrets
            , options = Nothing
            }
            (\session ->
                let
                    darkMode : Bool
                    darkMode =
                        (session |> Session.get "mode" |> Maybe.withDefault "light")
                            == "dark"
                in
                ( session
                , { darkMode = darkMode }
                )
            )
view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared model =
  { title = "My Page"
  , body = [
    Html.div [
      if app.data.darkMode then
        class "dark"
      else
        class "light"
     ]
     [
      -- ...
     ]
  ]
  }

```
