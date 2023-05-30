---
description: Route Modules are the blueprint for a route in elm-pages.
---

# Route Modules

Route Modules are Elm modules in the `app/Route` folder that define a top-level `route`.

You build the `route` using a builder chain, adding complexity as needed. You can scaffold a simple stateless page with `elm-pages run AddRoute Hello.Name_`. That gives you `app/Route/Hello/Name_.elm`.

```elm
module Route.Hello.Name_ exposing (Model, Msg, StaticData, route)

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
