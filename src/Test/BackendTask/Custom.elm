module Test.BackendTask.Custom exposing
    ( simulate
    , ensure
    )

{-| Simulate and assert on `BackendTask.Custom.run` calls in BackendTask tests.


## Simulating

@docs simulate


## Assertions

@docs ensure

-}

import Expect exposing (Expectation)
import Json.Encode as Encode
import Test.BackendTask.Internal as Internal exposing (BackendTaskTest)


{-| Simulate a pending `BackendTask.Custom.run` call resolving with the given JSON value.
The port name must exactly match the first argument passed to `BackendTask.Custom.run`.

    import Json.Encode as Encode
    import Test.BackendTask.Custom as BackendTaskCustom

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskCustom.simulate "hashPassword" (Encode.string "hashed_secret123")
        |> BackendTaskTest.expectSuccess

-}
simulate : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulate portName jsonResponse =
    Internal.simulateCustom portName jsonResponse


{-| Assert that a `BackendTask.Custom.run` call with the given port name is currently
pending, and run an assertion on the input arguments. Does not resolve the request.

    import Expect
    import Json.Decode as Decode
    import Test.BackendTask.Custom as BackendTaskCustom

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskCustom.ensure "hashPassword"
            (\args ->
                Decode.decodeValue Decode.string args
                    |> Expect.equal (Ok "secret123")
            )
        |> ...

-}
ensure : String -> (Encode.Value -> Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensure portName bodyAssertion =
    Internal.ensureCustom portName bodyAssertion
