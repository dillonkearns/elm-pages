---
description: Route Modules are the blueprint for a route in elm-pages.
---

# Route Modules

Route Modules are Elm modules in the `app/Route` folder that define a top-level `route`.

You build the `route` using a builder chain, adding complexity as needed. You can scaffold a simple stateless page with `elm-pages run AddRoute Hello.Name_`. That gives you `app/Route/Hello/Name_.elm`.

```elm
module Route.Blog.Slug_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (..)
import Html.Attributes as Attr
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import UrlPath
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { slug : String }


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { data = data
        , head = head
        , pages = pages
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask FatalError (List RouteParams)
pages =
    BackendTask.succeed [ { slug = "introducing-elm-pages" } ]

view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = app.routeParams.slug
    , body = [ h2 (text app.routeParams.slug)
             , p [ text app.data.body ]
             ]
    }

type alias Data = { body : String }

data : RouteParams -> BackendTask FatalError Data
data routeParams =
    "posts/" ++ routeParams.slug ++ ".md"
        |> BackendTask.File.rawFile
        |> BackendTask.allowFatal
        |> BackendTask.map Data
```
