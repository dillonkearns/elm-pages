---
description: Page Modules are the blueprint for a route in elm-pages.
---

# Page Modules

Page Templates are Elm modules in the `src/Page` folder that define a top-level `page`.

You build the `template` using a builder chain, adding complexity as needed. You can scaffold a simple stateless page with `elm-pages add Hello.Name_`. That gives you `src/Page/Hello/Name_.elm`.

```elm
module Template.Hello.Name_ exposing (Model, Msg, StaticData, template)

import DataSource
import View exposing (View)
import Head
import Head.Seo as Seo
import Html exposing (text)
import Pages.ImagePath as ImagePath
import Shared
import Template exposing (StaticPayload, Template)

type alias Route = { name : String }

type alias StaticData = ()

type alias Model = ()

type alias Msg = Never

template : Template Route StaticData
template =
    Template.noStaticData
        { head = head
        , staticRoutes = DataSource.succeed [ { name = "world" } ]
        }
        |> Template.buildNoState { view = view }


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
