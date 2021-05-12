# File-Based Routing

`elm-pages` gives you a router based on the Elm modules in your `src/Page` folder.

There

## Example routes

| File                               | Matching Routes                              | RouteParams                                                         |
| ---------------------------------- | -------------------------------------------- | ------------------------------------------------------------------- |
| `src/Page/Index.elm`               | `/`                                          | `{}`                                                                |
| `src/Page/Blog.elm`                | `/blog`                                      | `{}`                                                                |
| `src/Page/Blog/Slug_.elm`          | `/blog/:slug`                                | `{ slug : String }`                                                 |
| `src/Page/Docs/Section__.elm`      | `/docs` and `/docs/:section`                 | `{ slug : Maybe String }`                                           |
| `src/Repo/User_/Name_/SPLAT_.elm`  | `/repo/dillonkearns/elm-markdown/elm.json`   | `{ user : String, name : String, splat : ( String, List String ) }` |
| `src/Repo/User_/Name_/SPLAT__.elm` | Above and `/repo/dillonkearns/elm-markdown/` | `{ user : String, name : String, splat : List String }`             |

So Page Modules map to a route. That route can have RouteParams or not. If there are no RouteParams, you don't need to specify how to handle route parameters:

```elm
type alias RouteParams = {}


page : Page RouteParams Data
page =
    Page.singleRoute
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
    Page.prerenderedRoute
        { data = data
        , head = head
        , routes = routes
        }
        |> Page.buildNoState { view = view }


routes : DataSource.DataSource (List RouteParams)
routes =
    DataSource.succeed [ { slug = "introducing-elm-pages" } ]
```

And since `DataSource`s can come from anywhere, you could get that same data from `DataSource.Http`, `DataSource.Glob`, or any combination of `DataSource`s.

Often it's helpful to extract helper functions to make sure your routes are in sync with other `DataSource`s. For example, in your blog index page, you'd want to make sure
you display the same blog posts as you build routes for.

### Request-Time Routes

You can also handle routes on the server-side at request-time. The tradeoff is that rather than servering HTML and JSON files from the build step, your server will need to
build the page when the user requests it.

On the other hand, that means that you can access the incoming Request, including headers and query parameters.
