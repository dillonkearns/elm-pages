module BackendTask.Random exposing (generate)

{-|

@docs generate

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

-}
generate : Random.Generator value -> BackendTask error value
generate generator =
    randomSeed
        |> BackendTask.map
            (\seed ->
                Random.step generator seed |> Tuple.first
            )


randomSeed : BackendTask error Random.Seed
randomSeed =
    BackendTask.Internal.Request.request
        { name = "randomSeed"
        , body =
            BackendTask.Http.jsonBody Encode.null
        , expect =
            BackendTask.Http.expectJson
                (Decode.int |> Decode.map Random.initialSeed)
        }
