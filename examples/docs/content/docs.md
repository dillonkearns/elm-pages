## What is elm-pages

- Pre-render routes to HTML
- Hydrate to a full Elm app, with client-side navigation after initial load
- A file-based router
- `BackendTask`s allow you to pull data in to a given page and have it available before load
- A nice type-safe API for SEO
- Generate files, like RSS, sitemaps, podcast feeds, or any other strings you can output with pure Elm

## Getting Started

### CLI commands

- `elm-pages dev` - Run a dev server
- `elm-pages add Slide.Number_` Generate scaffolding for a new Page Module
- `elm-pages build` - run a full production build

### The dev server

`elm-pages dev` gives you a dev server with hot module replacement built-in. It even reloads your `BackendTask`s any time you change them.

## The elm-pages philosophy

#### Users build features, frameworks provide building blocks

Many frameworks provide features like

- Markdown parsing
- Special frontmatter directives
- RSS reader generation.

You can do all those things with `elm-pages`, but using the core building blocks

- The BackendTasks API lets you read from a file, parse frontmatter, and more. `elm-pages` helps you get the data.
- The data you get from any of those data sources is just typed Elm data. You decide what it means and how to use it.

The goal of `elm-pages` is to get nicely typed data from the right sources (HTTP, files, structured formats like JSON, markdown, etc.), and get that data to the right places in order to build an optimized site with good SEO.

## File Structure

With `elm-pages`, you don't define the central `main` entrypoint. That's defined under the hood by `elm-pages`.

It builds your app for you from these special files that you define:

#### `Shared.elm`

Must expose

- `template : SharedTemplate Msg Model StaticData msg`
- `Msg` - global `Msg`s across the whole app, like toggling a menu in the shared header view
- `Model` - shared state that persists between page navigations. This `Shared.Model` can be accessed by Page Modules.
- `SharedMsg` (todo - this needs to be documented better. Consider whether there could be an easier way to wire this in for users, too)

#### `Site.elm`

Must expose

- `config : SiteConfig StaticData`

#### `Document.elm`

Defines the types for your applications view.
Must expose

- A type called `Document msg` (must have exactly one type variable)
- `map : (msg1 -> msg2) -> Document msg1 -> Document msg2`

- `static/index.js` - same as previous `beta-index.js`
- `static/style.css` - same as previous `beta-style.css`

## File-Based Routing

`elm-pages` gives you a router based on the Elm modules in your `src/Page` folder.

There

### Example routes

| File                      | Matching Routes | RouteParams         |
| ------------------------- | --------------- | ------------------- |
| `src/Page/Index.elm`      | `/`             | `{}`                |
| `src/Page/Blog.elm`       | `/blog`         | `{}`                |
| `src/Page/Blog/Slug_.elm` | `/blog/:slug`   | `{ slug : String }` |

## Page Modules

Page Modules are Elm modules in the `src/Page` folder that define a top-level `page`.

You build the `page` using a builder chain, adding complexity as needed. You can scaffold a simple stateless page with `elm-pages add Hello.Name_`. That gives you `src/Page/Hello/Name_.elm`.

```elm
module Page.Hello.Name_ exposing (Model, Msg, StaticData, page)

import BackendTask
import View exposing (View)
import Head
import Head.Seo as Seo
import Html exposing (text)
import Pages.ImagePath as ImagePath
import Shared
import Page exposing (StaticPayload, Page)

type alias Route = { name : String }

type alias StaticData = ()

type alias Model = ()

type alias Msg = Never

page : Page Route StaticData
page =
    Page.noStaticData
        { head = head
        , staticRoutes = BackendTask.succeed [ { name = "world" } ]
        }
        |> Page.buildNoState { view = view }


head :
    StaticPayload StaticData Route
    -> List Head.Tag
head static = [] -- SEO tags here

view :
    StaticPayload StaticData Route
    -> Document Msg
view static =
    { title = "Hello " ++ static.routeParams.name
    , body = [ text <| "👋 " ++ static.routeParams.name ]
    }
```

## `BackendTask`s

It doesn't matter _where_ a `BackendTask` came from.

For example, if you have

```elm
type alias Author =
    { name : String
    , avatarUrl : String
    }

authors : BackendTask (List Author)
```

It makes no difference where that data came from. In fact, let's define it as hardcoded data:

```elm
hardcodedAuthors : BackendTask (List Author)
hardcodedAuthors =
    BackendTask.succeed [
        { name = "Dillon Kearns"
        , avatarUrl = "/avatars/dillon.jpg"
        }
    ]
```

We could swap that out to get the data from another source at any time. Like this HTTP BackendTask.

```elm
authorsFromCms : BackendTask (List Author)
authorsFromCms =
    BackendTask.Http.get (Secrets.succeed "mycms.com/authors")
        authorsDecoder
```

Notice that the type signature hasn't changed. The end result will be data that is available when our page loads.

In fact, let's combine our library of authors from 3 different `BackendTask`s.

```elm
authorsFromFile : BackendTask (List Author)
authorsFromFile =
    BackendTask.File.read "data/authors.json"
        authorsDecoder

allAuthors : BackendTask (List Author)
allAuthors =
    BackendTask.map3 (\authors1 authors2 authors3 ->
        List.concat [ authors1, authors2, authors3 ]
    )
    authorsFromFile
    authorsFromCms
    hardcodedAuthors
```

So how does the data get there? Let's take a look at the lifecycle of a BackendTask.

### The `BackendTask` Lifecycle

A `BackendTask` is split between two phases:

1. Build step - build up the data for a given page
2. Decode the data - it's available without reading files or making HTTP requests from the build step

That means that when we run `elm-pages build`, then deploy the HTML and JSON output from the build to a CDN, it will not hit `mycms.com/authors` anymore.

So when a user goes to your site, they won't hit your CMS directly. Instead, when they load the page it will include all of the data that we used for that specific page
in the initial load. That's how `elm-pages` can skip the loading spinner for an HTTP data source - it builds the data into the page at build-time.

### Optimized Decoders

Often REST APIs will include a lot of data that you can use. But you might need just a couple of fields.

When you write an `OptimizedDecoder`, `elm-pages` will only include the JSON data that you decoded when it builds that page.

For example, the GitHub API returns back dozens of fields in this API response, but we only want one: the number of stargazers.

```elm
import OptimizedDecoder
import BackendTask exposing (BackendTask)

staticData : BackendTask Int
staticData =
    BackendTask.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (OptimizedDecoder.field "stargazers_count" OptimizedDecoder.int)
```

That means the data that gets built into the site will be:

```json
{ "stargazers_count": 123 }
```

At build-time, `elm-pages` performs this optimization, which means your users don't have to pay the cost of running it when your site loads in their browser - they get the best of both worlds with a smaller JSON payload, and a fast decoder!

## File-Based Routes

| File                      | Matching Routes | RouteParams         |
| ------------------------- | --------------- | ------------------- |
| `src/Page/Index.elm`      | `/`             | `{}`                |
| `src/Page/Blog.elm`       | `/blog`         | `{}`                |
| `src/Page/Blog/Slug_.elm` | `/blog/:slug`   | `{ slug : String }` |

### Where are data sources used
