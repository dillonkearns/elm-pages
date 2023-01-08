---
description: TODO
---

# `BackendTask`s

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
    BackendTask.File.jsonFile "data/authors.json"
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

## The `BackendTask` Lifecycle

A `BackendTask` is split between two phases:

1. Build step - build up the data for a given page
2. Decode the data - it's available without reading files or making HTTP requests from the build step

That means that when we run `elm-pages build`, then deploy the HTML and JSON output from the build to a CDN, it will not hit `mycms.com/authors` anymore.

So when a user goes to your site, they won't hit your CMS directly. Instead, when they load the page it will include all of the data that we used for that specific page
in the initial load. That's how `elm-pages` can skip the loading spinner for an HTTP data source - it builds the data into the page at build-time.

## Optimized Decoders

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
