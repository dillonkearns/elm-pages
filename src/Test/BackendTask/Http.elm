module Test.BackendTask.Http exposing
    ( simulateGet, simulatePost, simulate, simulateError
    , HttpError(..)
    , ensureGet, ensurePost
    )

{-| Simulate and assert on HTTP requests in BackendTask tests.


## Simulating HTTP Responses

@docs simulateGet, simulatePost, simulate, simulateError


## HTTP Errors

@docs HttpError


## Assertions

@docs ensureGet, ensurePost

-}

import Expect exposing (Expectation)
import Json.Encode as Encode
import Test.BackendTask.Internal as Internal exposing (BackendTaskTest)


{-| The type of HTTP error to simulate with [`simulateError`](#simulateError).

    import Test.BackendTask.Http as BackendTaskHttp

    BackendTaskHttp.simulateError
        "GET"
        "https://api.example.com/data"
        BackendTaskHttp.NetworkError

-}
type HttpError
    = NetworkError
    | Timeout


{-| Simulate a pending HTTP GET request resolving with the given JSON response body.

    import Json.Encode as Encode
    import Test.BackendTask.Http as BackendTaskHttp

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskHttp.simulateGet
            "https://api.example.com/data"
            (Encode.object [ ( "key", Encode.string "value" ) ])
        |> BackendTaskTest.expectSuccess

-}
simulateGet : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateGet url jsonResponse =
    Internal.simulateHttpGet url jsonResponse


{-| Simulate a pending HTTP POST request resolving with the given JSON response body.

    import Json.Encode as Encode
    import Test.BackendTask.Http as BackendTaskHttp

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskHttp.simulatePost
            "https://api.example.com/items"
            (Encode.object [ ( "id", Encode.int 42 ) ])
        |> BackendTaskTest.expectSuccess

-}
simulatePost : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulatePost url jsonResponse =
    Internal.simulateHttpPost url jsonResponse


{-| Simulate any HTTP request with full control over method, status code, headers, and body.

    import Test.BackendTask.Http as BackendTaskHttp
    import Json.Encode as Encode

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskHttp.simulate
            { method = "PUT", url = "https://api.example.com/item/1" }
            { statusCode = 204
            , statusText = "No Content"
            , headers = []
            , body = Encode.null
            }
        |> BackendTaskTest.expectSuccess

-}
simulate :
    { method : String, url : String }
    -> { statusCode : Int, statusText : String, headers : List ( String, String ), body : Encode.Value }
    -> BackendTaskTest a
    -> BackendTaskTest a
simulate request response =
    Internal.simulateHttp request response


{-| Simulate a pending HTTP request failing with an [`HttpError`](#HttpError).

    import Test.BackendTask.Http as BackendTaskHttp

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskHttp.simulateError "GET" "https://api.example.com/data" BackendTaskHttp.NetworkError
        |> BackendTaskTest.expectFailure

-}
simulateError : String -> String -> HttpError -> BackendTaskTest a -> BackendTaskTest a
simulateError method url error =
    let
        errorString =
            case error of
                NetworkError ->
                    "NetworkError"

                Timeout ->
                    "Timeout"
    in
    Internal.simulateHttpError method url errorString


{-| Assert that a GET request to the given URL is currently pending, without resolving it.
Useful for verifying that requests are dispatched in parallel.

    import Test.BackendTask.Http as BackendTaskHttp

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskHttp.ensureGet "https://api.example.com/a"
        |> BackendTaskHttp.ensureGet "https://api.example.com/b"
        |> ...

-}
ensureGet : String -> BackendTaskTest a -> BackendTaskTest a
ensureGet url =
    Internal.ensureHttpGet url


{-| Assert that a POST request to the given URL is currently pending, and run an
assertion on the request body. Does not resolve the request.

    import Expect
    import Json.Decode as Decode
    import Test.BackendTask.Http as BackendTaskHttp

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskHttp.ensurePost "https://api.example.com/items"
            (\body ->
                Decode.decodeValue (Decode.field "name" Decode.string) body
                    |> Expect.equal (Ok "test")
            )
        |> ...

-}
ensurePost : String -> (Encode.Value -> Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensurePost url bodyAssertion =
    Internal.ensureHttpPost url bodyAssertion
