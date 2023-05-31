module Test.Http exposing
    ( expectJsonBody, HttpRequest, hasHeader
    , timeout, networkError, httpResponse
    )

{-| Convenience functions for testing HTTP requests.
_Pull requests are welcome to add more useful functions._


## Expectations

These functions provide some convenient checks that can be used with [`ProgramTest.expectHttpRequest`](ProgramTest#expectHttpRequest).

@docs expectJsonBody, HttpRequest, hasHeader


## Responses

These are ways to easily make `Http.Response` values for use with [`ProgramTest.simulateHttpResponse`](ProgramTest#simulateHttpResponse).

@docs timeout, networkError, httpResponse

-}

import Dict exposing (Dict)
import Expect exposing (Expectation)
import Http
import Json.Decode
import SimulatedEffect exposing (SimulatedTask)


{-| -}
type alias HttpRequest x a =
    { method : String
    , url : String
    , body : String
    , headers : List ( String, String )
    , onRequestComplete : Http.Response String -> SimulatedTask x a
    }


{-| A convenient way to check something about the request body of a pending HTTP request.

    ...
        |> ProgramTest.expectHttpRequest "POST"
            "https://example.com/ok"
            (Test.Http.expectJsonBody
                (Json.Decode.field "version" Json.Decode.string)
                (Expect.equal "3.1.5")
            )

-}
expectJsonBody :
    Json.Decode.Decoder requestBody
    -> (requestBody -> Expectation)
    -> HttpRequest x a
    -> Expectation
expectJsonBody decoder check request =
    case Json.Decode.decodeString decoder request.body of
        Err err ->
            Expect.fail ("expectJsonBody: Failed to decode HTTP request body: " ++ Json.Decode.errorToString err)

        Ok responseBody ->
            check responseBody


{-| Assert that the given HTTP request has the specified header.

    ...
        |> ProgramTest.expectHttpRequest "POST"
            "https://example.com/ok"
            (Test.Http.hasHeader "Content-Type" "application/json")

-}
hasHeader : String -> String -> HttpRequest x a -> Expectation
hasHeader key value { headers } =
    let
        key_ =
            String.toLower key

        value_ =
            String.toLower value

        matches ( k, v ) =
            ( String.toLower k, String.toLower v )
                == ( key_, value_ )
    in
    if List.any matches headers then
        Expect.pass

    else
        Expect.fail <|
            String.join "\n"
                [ "Expected HTTP header " ++ key ++ ": " ++ value
                , "but got headers:"
                , List.map (\( k, v ) -> "    " ++ k ++ ": " ++ v) headers
                    |> String.join "\n"
                ]


{-| This is the same as `Http.Timeout_`,
but is exposed here so that your test doesn't need to import both `Http` and `Test.Http`.
-}
timeout : Http.Response body
timeout =
    Http.Timeout_


{-| This is the same as `Http.NetworkError_`,
but is exposed here so that your test doesn't need to import both `Http` and `Test.Http`.
-}
networkError : Http.Response body
networkError =
    Http.NetworkError_


{-| This is a more convenient way to create `Http.BadStatus_` and `Http.GoodStatus_` values.

Following the [logic in elm/http](https://github.com/elm/http/blob/2.0.0/src/Elm/Kernel/Http.js#L65),
this will produce `Http.GoodStatus_` if the given status code is in the 200 series, otherwise
it will produce `Http.BadStatus_`.

-}
httpResponse :
    { statusCode : Int
    , headers : List ( String, String )
    , body : body
    }
    -> Http.Response body
httpResponse response =
    let
        variant =
            if response.statusCode >= 200 && response.statusCode < 300 then
                Http.GoodStatus_

            else
                Http.BadStatus_
    in
    variant
        { url = ""
        , statusCode = response.statusCode
        , statusText = "TODO: if you need this, please report to https://github.com/avh4/elm-program-test/issues"
        , headers = Dict.fromList response.headers
        }
        response.body
