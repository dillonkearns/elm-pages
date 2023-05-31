module BackendTask.Random exposing
    ( generate
    , int32
    )

{-|

@docs generate

@docs int32

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Json.Decode as Decode
import Json.Encode as Encode
import Random


{-| Takes an `elm/random` `Random.Generator` and runs it using a randomly generated initial seed.

    type alias Data =
        { randomData : ( Int, Float )
        }

    data : BackendTask FatalError Data
    data =
        BackendTask.map Data
            (BackendTask.Random.generate generator)

    generator : Random.Generator ( Int, Float )
    generator =
        Random.map2 Tuple.pair (Random.int 0 100) (Random.float 0 100)

The random initial seed is generated using <https://developer.mozilla.org/en-US/docs/Web/API/Crypto/getRandomValues>
to generate a single 32-bit Integer. That 32-bit Integer is then used with `Random.initialSeed` to create an Elm Random.Seed value.
Then that `Seed` used to run the `Generator`.

Note that this is different than `elm/random`'s `Random.generate`. This difference shouldn't be problematic, and in fact the `BackendTask`
random seed generation is more cryptographically independent because you can't determine the
random seed based solely on the time at which it is run. Each time you call `BackendTask.generate` it uses a newly
generated random seed to run the `Random.Generator` that is passed in. In contrast, `elm/random`'s `Random.generate`
generates an initial seed using `Time.now`, and then continues with that same seed using using [`Random.step`](https://package.elm-lang.org/packages/elm/random/latest/Random#step)
to get new random values after that. You can [see the implementation here](https://github.com/elm/random/blob/c1c9da4d861363cee1c93382d2687880279ed0dd/src/Random.elm#L865-L896).
However, `elm/random` is still not suitable in general for cryptographic uses of random because it uses 32-bits for when it
steps through new seeds while running a single `Random.Generator`.

-}
generate : Random.Generator value -> BackendTask error value
generate generator =
    int32
        |> BackendTask.map
            (Random.initialSeed
                >> Random.step generator
                >> Tuple.first
            )


{-| Gives a random 32-bit Int. This can be useful if you want to do low-level things with a cryptographically sound
random 32-bit integer.

The value comes from running this code in Node using <https://developer.mozilla.org/en-US/docs/Web/API/Crypto/getRandomValues>:

```js
import * as crypto from "node:crypto";

crypto.getRandomValues(new Uint32Array(1))[0]
```

-}
int32 : BackendTask error Int
int32 =
    BackendTask.Internal.Request.request
        { name = "randomSeed"
        , body = BackendTask.Http.jsonBody Encode.null
        , expect = BackendTask.Http.expectJson Decode.int
        }
