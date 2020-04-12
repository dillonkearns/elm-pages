module Pages.Secrets exposing (Value, map, succeed, with)

{-| Secrets are a secure way to use environment variables in your StaticHttp requests. The actual environment
variable value is used to perform StaticHttp requests, while the masked value is the only thing that ends up in your
built site. Let's go through what happens in a concrete example:


## Example

Let's say you execute this from the shell:

```shell
GITHUB_TOKEN=abcd1234 API_KEY=xyz789 elm-pages build
```

And your StaticHttp request in your Elm code looks like this:

    import Pages.Secrets as Secrets
    import Pages.StaticHttp as StaticHttp

    StaticHttp.request
        (Secrets.succeed
            (\apiKey githubToken ->
                { url = "https://api.github.com/repos/dillonkearns/elm-pages?apiKey=" ++ apiKey
                , method = "GET"
                , headers = [ ( "Authorization", "Bearer " ++ githubToken ) ]
                }
            )
            |> Secrets.with "API_KEY"
            |> Secrets.with "BEARER"
        )
        (Decode.succeed ())
    )

The following masked values are what will be visible in your production bundle if you inspect the code or the Network tab:

    [GET]https://api.github.com/repos/dillonkearns/elm-pages?apiKey=<API_KEY>Authorization : Bearer <BEARER>

So the actual Secrets only exist for the duration of the build in order to perform the StaticHttp requests, but they
are replaced with `<SECRET_NAME>` once that step is done and your assets are bundled.

@docs Value, map, succeed, with

-}

import Secrets


{-| Represents a Secure value from your environment variables. `Pages.Secrets.Value`s are much like `Json.Decode.Value`s
in that you can take raw values, map them, and combine them with other values into any data structure.
-}
type alias Value value =
    Secrets.Value value


{-| Hardcode a secret value. Or, this can be used to start a pipeline-style value with several different secrets (see
the example at the top of this page).

    import Pages.Secrets as Secrets

    Secrets.succeed "hardcoded-secret"

-}
succeed : value -> Value value
succeed =
    Secrets.succeed


{-| Map a Secret's raw value into an arbitrary type or value.
-}
map : (valueA -> valueB) -> Value valueA -> Value valueB
map =
    Secrets.map


{-| Allows you to chain together multiple secrets. See the top of this page for a full example.
-}
with : String -> Value (String -> value) -> Value value
with =
    Secrets.with
