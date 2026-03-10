module Test.BackendTask.Stream exposing
    ( simulateCustomStream, simulateStreamHttp
    )

{-| Simulate stream pipelines containing opaque parts in BackendTask tests.


## Simulating

@docs simulateCustomStream, simulateStreamHttp

-}

import Test.BackendTask.Internal as Internal exposing (BackendTaskTest)


{-| Simulate a pending stream pipeline containing a custom stream part
(`Stream.customRead`, `Stream.customWrite`, or `Stream.customDuplex`).
The framework handles simulatable parts around the custom part. You only
provide its output.

    import Test.BackendTask.Stream as BackendTaskStream

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskStream.simulateCustomStream "myTransform" "transformed output"
        |> BackendTaskTest.expectSuccess

-}
simulateCustomStream : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateCustomStream portName portOutput =
    Internal.simulateCustomStream portName portOutput


{-| Simulate a pending stream pipeline containing an HTTP stream part
(`Stream.http` or `Stream.httpWithInput`). The framework handles simulatable
parts around the HTTP request. You only provide the response body.

    import Test.BackendTask.Stream as BackendTaskStream

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskStream.simulateStreamHttp "https://api.example.com" "response body"
        |> BackendTaskTest.expectSuccess

-}
simulateStreamHttp : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateStreamHttp url httpOutput =
    Internal.simulateStreamHttp url httpOutput
