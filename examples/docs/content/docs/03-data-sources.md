# `DataSource`s

## The `DataSource` Lifecycle

A `DataSource` is split between two phases:

1. Build step - build up the data for a given page
2. Decode the data - it's available without reading files or making HTTP requests from the build step

| File                      | Matching Routes | RouteParams         |
| ------------------------- | --------------- | ------------------- |
| `src/Page/Index.elm`      | `/`             | `{}`                |
| `src/Page/Blog.elm`       | `/blog`         | `{}`                |
| `src/Page/Blog/Slug_.elm` | `/blog/:slug`   | `{ slug : String }` |

## Where are data sources used
