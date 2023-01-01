---
description: TODO
---

# File-Based Routing

`elm-pages` gives you a router based on the Elm modules in your `src/Page` folder.

## Example routes

| File                               | Matching Routes                              | RouteParams                                                         |
| ---------------------------------- | -------------------------------------------- | ------------------------------------------------------------------- |
| `src/Page/Index.elm`               | `/`                                          | `{}`                                                                |
| `src/Page/Blog.elm`                | `/blog`                                      | `{}`                                                                |
| `src/Page/Blog/Slug_.elm`          | `/blog/:slug`                                | `{ slug : String }`                                                 |
| `src/Page/Docs/Section__.elm`      | `/docs` and `/docs/:section`                 | `{ section : Maybe String }`                                        |
| `src/Repo/User_/Name_/SPLAT_.elm`  | `/repo/dillonkearns/elm-markdown/elm.json`   | `{ user : String, name : String, splat : ( String, List String ) }` |
| `src/Repo/User_/Name_/SPLAT__.elm` | Above and `/repo/dillonkearns/elm-markdown/` | `{ user : String, name : String, splat : List String }`             |

So Page Modules map to a route. That route can have RouteParams or not. If there are no RouteParams, you don't need to specify how to handle route parameters:

```elm
type alias RouteParams = {}


page : Page RouteParams Data
page =
    Page.single
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }
```

If there are RouteParams, then you need to let `elm-pages` know which routes to handle.

### Build-Time Routes

```elm
type alias RouteParams =
    { slug : String }


page : Page RouteParams Data
page =
    Page.preRender
        { data = data
        , head = head
        , routes = routes
        }
        |> Page.buildNoState { view = view }


routes : BackendTask.BackendTask (List RouteParams)
routes =
    BackendTask.succeed [ { slug = "introducing-elm-pages" } ]
```

And since `BackendTask`s can come from anywhere, you could get that same data from `BackendTask.Http`, `BackendTask.Glob`, or any combination of `BackendTask`s.

Often it's helpful to extract helper functions to make sure your routes are in sync with other `BackendTask`s. For example, in your blog index page, you'd want to make sure
you display the same blog posts as you build routes for.

### Request-Time Routes

You can also handle routes on the server-side at request-time. The tradeoff is that rather than servering HTML and JSON files from the build step, your server will need to
build the page when the user requests it.

On the other hand, that means that you can access the incoming Request, including headers and query parameters.

## Static Segments

Any part of the module that doesn't end with an underscore (`_`) is a static segment.

For example, in `src/Page/About.elm`, about is a static segment, so the URL `/about` will route to this module.

Static segments are `CapitalCamelCase` in Elm module names, and are `kebab-case` in the URL. So `src/Page/OurTeam.elm` will handle the URL `/our-team`.

Segments can be nested. So `src/Page/Jobs/Marketing` will handle the URL `/jobs/marketing`.

There is one special static segment name: Index. You'll only need this for your root route. So `src/Page/Index.elm` will handle the URL `/`.

## Dynamic Segments

Segments ending with an underscore (`_`) are dynamic segments. You can mix static and dynamic segments. For example, `src/Page/Blog/Slug_.elm` will handle URLs like `/blog/my-post`.

You can have two dynamic segments. `src/Page/Episode/Show_/SeasonNumber_/EpisodeNumber_.elm` will handle URLs like `/episode/simpsons/3/1`. The resulting URL will be give you RouteParams `{ show = "simpsons", seasonNumber = "3", episodeNumber = "1" }`.

## Special Ending Segments

The final segment can use one of the following special handlers:

1. Optional Dynamic Segment
2. Splat
3. Optional Splat

These cannot be used anywhere except for the final segment. That means no static, dynamic, or other segments can come after it in a Page module.

## Optional Dynamic Segments

`src/Page/Docs/Section__.elm` will match both `/docs/getting-started` as well as `/docs`. This is often useful when you want to treat a route as the default. You could use a static segment instead to handle `/docs` with `src/Page/Docs`. The choice depends on whether you want to use a separate Page Module to handle those routes or not. In the case of these docs, `/docs` shows the first docs page so it uses an optional segment.

## Splat Routes

Splat routes allow you to do a catch all to catch 1 or more segments at the end of the route. If you want to have all of your routes defined from a CMS, then you can use `src/Page.SPLAT_.elm`. That will match any URL except for the root route (`/`).

You can have any number of static segments and dynamic segments before the SPLAT\_ and it will match as usual. For example, `src/Page/City/SPLAT_.elm` could be used to match the following:

| URL                               | RouteParams                                             |
| --------------------------------- | ------------------------------------------------------- |
| `/city/paris`                     | `{ splat = ( "paris", [] ) }`                           |
| `/city/france/paris`              | `{ splat = ( "france", [ "paris" ] ) }`                 |
| `/city/us/california/los-angeles` | `{ splat = ( "us", [ "california", "los-angeles" ] ) }` |

## Optional Splat Routes

Exactly like a Splat route, except that it matches 0 or more segments (not 1 or more). The splat data in RouteParams for an optional splat are `List String` rather than `(String, List String)` to represent the fact that optional splat routes could match 0 segments.
