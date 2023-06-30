---
description: The routing for an elm-pages app is defined from the Elm modules in the `app/Route` folder.
---

# File-Based Routing

`elm-pages` gives you a router based on the Elm modules in your `app/Route` folder.

## Example routes

| File                                     | Matching Routes                              | RouteParams                                                         |
| ---------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------- |
| `app/Route/Index.elm`                    | `/`                                          | `{}`                                                                |
| `app/Route/Blog.elm`                     | `/blog`                                      | `{}`                                                                |
| `app/Route/Blog/Slug_.elm`               | `/blog/:slug`                                | `{ slug : String }`                                                 |
| `app/Route/Docs/Section__.elm`           | `/docs` and `/docs/:section`                 | `{ section : Maybe String }`                                        |
| `app/Route/Repo/User_/Name_/SPLAT_.elm`  | `/repo/dillonkearns/elm-markdown/elm.json`   | `{ user : String, name : String, splat : ( String, List String ) }` |
| `app/Route/Repo/User_/Name_/SPLAT__.elm` | Above and `/repo/dillonkearns/elm-markdown/` | `{ user : String, name : String, splat : List String }`             |

So Route Modules map to a route. That route can have `RouteParams` or not. If there are no `RouteParams`, you don't need to specify how to handle route parameters:

```elm
type alias RouteParams = {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }
```

If there are RouteParams, then you need to let `elm-pages` know which routes to handle.

### Build-Time Routes

```elm
type alias RouteParams =
    { slug : String }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState
            { view = view }


pages : BackendTask.BackendTask (List RouteParams)
pages =
    BackendTask.succeed [ { slug = "introducing-elm-pages" } ]
```

And since `BackendTask`s can come from anywhere, you could get that same data from `BackendTask.Http`, `BackendTask.Glob`, or any combination of `BackendTask`s.

Often it's helpful to extract helper functions to make sure your routes are in sync with other `BackendTask`s. For example, in your blog index page, you'd want to make sure
you display the same blog posts as you build routes for.

### Request-Time Routes

You can also handle routes on the server-side at request-time. The tradeoff is that rather than servering HTML and JSON files from the build step, your server will need to
build the page when the user requests it.

On the other hand, that means that you can access the incoming Request, including headers and query parameters. It also means you can deal with unlimited possible pages since they are rendered on demand.

```elm
type alias RouteParams =
    { slug : String }


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.buildWithLocalState
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
        (RouteBuilder.serverRender { data = data, action = action, head = head })

data :
    RouteParams
    -> Request
    -> BackendTask FatalError (ServeResponse Data ErrorPage)
data routeParams request =
    if routeParams.slug == "new" then
        Server.Response.render
            { post =
                { slug = ""
                , title = ""
                , body = ""
                , publish = Nothing
                }
            }
            |> BackendTask.succeed

    else
        BackendTask.Custom.run "getPost"
            (Encode.string routeParams.slug)
            (Decode.nullable Post.decoder)
            |> BackendTask.allowFatal
            |> BackendTask.map
                (\maybePost ->
                    case maybePost of
                        Just post ->
                            Server.Response.render
                                { post = post
                                }

                        Nothing ->
                            Server.Response.errorPage ErrorPage.NotFound
                )
```

## Static Segments

Any part of the module that doesn't end with an underscore (`_`) is a static segment.

For example, in `app/Route/About.elm`, about is a static segment, so the URL `/about` will route to this module.

Static segments are `CapitalCamelCase` in Elm module names, and are `kebab-case` in the URL. So `app/Route/OurTeam.elm` will handle the URL `/our-team`.

Segments can be nested. So `app/Route/Jobs/Marketing` will handle the URL `/jobs/marketing`.

There is one special static segment name: Index. You'll only need this for your root route. So `app/Route/Index.elm` will handle the URL `/`.

## Dynamic Segments

Segments ending with an underscore (`_`) are dynamic segments. You can mix static and dynamic segments. For example, `app/Route/Blog/Slug_.elm` will handle URLs like `/blog/my-post`.

You can have two dynamic segments. `app/Route/Episode/Show_/SeasonNumber_/EpisodeNumber_.elm` will handle URLs like `/episode/simpsons/3/1`. The resulting URL will be give you RouteParams `{ show = "simpsons", seasonNumber = "3", episodeNumber = "1" }`.

## Special Ending Segments

The final segment can use one of the following special handlers:

1. Optional Dynamic Segment
2. Splat
3. Optional Splat

These cannot be used anywhere except for the final segment. That means no static, dynamic, or other segments can come after it in a Route module.

## Optional Dynamic Segments

`app/Route/Docs/Section__.elm` will match both `/docs/getting-started` as well as `/docs`. This is often useful when you want to treat a route as the default. You could use a static segment instead to handle `/docs` with `app/Route/Docs`. The choice depends on whether you want to use a separate Route Module to handle those routes or not. In the case of these docs, `/docs` shows the first docs page so it uses an optional segment.

## Splat Routes

Splat routes allow you to do a catch all to catch 1 or more segments at the end of the route. If you want to have all of your routes defined from a CMS, then you can use `app/Route.SPLAT_.elm`. That will match any URL except for the root route (`/`).

You can have any number of static segments and dynamic segments before the SPLAT\_ and it will match as usual. For example, `app/Route/City/SPLAT_.elm` could be used to match the following:

| URL                               | RouteParams                                             |
| --------------------------------- | ------------------------------------------------------- |
| `/city/paris`                     | `{ splat = ( "paris", [] ) }`                           |
| `/city/france/paris`              | `{ splat = ( "france", [ "paris" ] ) }`                 |
| `/city/us/california/los-angeles` | `{ splat = ( "us", [ "california", "los-angeles" ] ) }` |

## Optional Splat Routes

Exactly like a Splat route, except that it matches 0 or more segments (not 1 or more). The splat data in RouteParams for an optional splat are `List String` rather than `(String, List String)` to represent the fact that optional splat routes could match 0 segments.
