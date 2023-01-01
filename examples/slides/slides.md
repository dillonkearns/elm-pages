## elm-pages 2.0

```
elm-pages add Projects.Username_.Repo_
```

```elm
type alias RouteParams =
    { username : String, repo : String }

page : Page RouteParams StaticData
page =
    Page.noStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed []
        }
        |> Page.buildNoState { view = view }


view :
    StaticPayload StaticData RouteParams
    -> Document Msg
view static =
    { title = "TODO title"
    , body = []
    }
```

## Core Concepts

- Page Modules (`Page.*.elm`)
- `BackendTask`s
- `Shared.elm`, `Site.elm`
