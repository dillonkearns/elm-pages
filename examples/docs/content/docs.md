## What is elm-pages

### The elm-pages philosophy

#### Users build features, frameworks provide building blocks

Many frameworks provide features like

- Markdown parsing
- Special frontmatter directives
- RSS reader generation.

You can do all those things with `elm-pages`, but using the core building blocks

- The DataSources API lets you read from a file, parse frontmatter, and more. `elm-pages` helps you get the data. Where you get that data from, and what you do with it are up to you.

The goal of `elm-pages` is to get nicely typed data from the right sources (HTTP, files, structured formats like JSON, markdown, etc.), and get that data to the right places in order to build an optimized site with good SEO.

## File-Based Routing

### Example routes

| File                      | Matching Routes | RouteParams         |
| ------------------------- | --------------- | ------------------- |
| `src/Page/Index.elm`      | `/`             | `{}`                |
| `src/Page/Blog.elm`       | `/blog`         | `{}`                |
| `src/Page/Blog/Slug_.elm` | `/blog/:slug`   | `{ slug : String }` |

## Page Templates

TODO

## `DataSource`s

It doesn't matter _where_ a `DataSource` came from.

For example, if you have

```elm
type alias Author =
    { name : String
    , avatarUrl : String
    }

upcomingEvents : DataSource (List Author)
```

It makes no difference where that data came from. In fact, let's define it as hardcoded data:

```elm
upcomingEvents : DataSource (List Author)
upcomingEvents =
    DataSource.succeed [
        { name = "Dillon Kearns"
        , avatarUrl = "/avatars/dillon.jpg"
        }
    ]
```

We could swap that out to get the data from another source at any time. Like this HTTP DataSource.

```elm
upcomingEvents : DataSource (List Author)
upcomingEvents =
    DataSource.Http.get (Secrets.succeed "mycms.com/authors")
        authorsDecoder
```

Notice that the type signature hasn't changed. The end result will be data that is available when our page loads.

So how does it get there? Let's take a look at the lifecycle of a DataSource.

### The `DataSource` Lifecycle

A `DataSource` is split between two phases:

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
import DataSource exposing (DataSource)

staticData : DataSource Int
staticData =
    DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
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
