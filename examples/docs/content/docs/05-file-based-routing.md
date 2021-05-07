# File-Based Routing

`elm-pages` gives you a router based on the Elm modules in your `src/Page` folder.

There

## Example routes

| File                      | Matching Routes | RouteParams         |
| ------------------------- | --------------- | ------------------- |
| `src/Page/Index.elm`      | `/`             | `{}`                |
| `src/Page/Blog.elm`       | `/blog`         | `{}`                |
| `src/Page/Blog/Slug_.elm` | `/blog/:slug`   | `{ slug : String }` |
