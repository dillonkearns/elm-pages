## elm-pages 2.0

```
elm-pages generate Projects.Username_.Repo_
```

```elm
type alias RouteParams =
    { username : String, repo : String }

template : Template RouteParams StaticData
template =
    Template.noStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed []
        }
        |> Template.buildNoState { view = view }


view :
    StaticPayload StaticData RouteParams
    -> Document Msg
view static =
    { title = "TODO title"
    , body = []
    }
```

## Core Concepts

- Page Templates (`Template.*.elm`)
- `DataSource`s
- `Shared.elm`, `Site.elm`

## Page Templates

Here's another body
