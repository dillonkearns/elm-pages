---
description: Error Handling
---

# Error Handling

1. Have a `FatalError` from data: https://github.com/dillonkearns/elm-pages-v3-beta/blob/49e5e26fd1aecf26c04006464e2252ff459385dd/examples/pokedex/app/Route/ErrorHandling.elm#L46-L51

2. Customize rendering of the InternalError variant in your ErrorPage to your liking: https://github.com/dillonkearns/elm-pages-v3-beta/blob/49e5e26fd1aecf26c04006464e2252ff459385dd/examples/pokedex/app/ErrorPage.elm#L124-L132

3. Custom 500 errors! https://mellow-scone-524810.netlify.app/error-handling

You can do different kinds of errors as well, like 401 or 403 or 404 error pages, but these are expected errors, not "something went really wrong" FatalError's.

```elm
Rendering a 404 looks like this for example:
Request.succeed
    (BackendTask.succeed
        (Response.errorPage ErrorPage.NotFound)
    )
```
