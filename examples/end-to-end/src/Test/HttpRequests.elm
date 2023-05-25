module Test.HttpRequests exposing (all)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Test exposing (Test)


all : BackendTask FatalError Test
all =
    [ BackendTask.Http.get "http://localhost:1234/error-code/500" (BackendTask.Http.expectWhatever ())
        |> BackendTask.mapError .recoverable
        |> test "http 500 error"
            (\result ->
                case result of
                    Err error ->
                        case error of
                            BackendTask.Http.BadStatus metadata string ->
                                metadata.statusCode
                                    |> Expect.equal 500

                            _ ->
                                Expect.fail ("Expected BadStatus, got :" ++ Debug.toString error)

                    Ok () ->
                        Expect.fail "Expected HTTP error, got Ok"
            )
    , BackendTask.Http.get "http://localhost:1234/error-code/404" (BackendTask.Http.expectWhatever ())
        |> BackendTask.mapError .recoverable
        |> test "http 404 error"
            (\result ->
                case result of
                    Err error ->
                        case error of
                            BackendTask.Http.BadStatus metadata string ->
                                metadata.statusCode
                                    |> Expect.equal 404

                            _ ->
                                Expect.fail ("Expected BadStatus, got: " ++ Debug.toString error)

                    Ok () ->
                        Expect.fail "Expected HTTP error, got Ok"
            )
    , BackendTask.Http.getJson "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.field "stargazers_count" Decode.int)
        |> BackendTask.mapError .recoverable
        |> test "200 JSON"
            (\result ->
                case result of
                    Err error ->
                        Expect.fail ("Expected BadStatus, got: " ++ Debug.toString error)

                    Ok count ->
                        Expect.pass
            )
    , BackendTask.Http.getJson "https://api.github.com/repos/dillonkearns/elm-pages" (Decode.field "this-field-doesn't-exist" Decode.int)
        |> BackendTask.mapError .recoverable
        |> test "JSON decoding error"
            (\result ->
                case result of
                    Err (BackendTask.Http.BadBody (Just (Decode.Failure failureString _)) _) ->
                        failureString
                            |> Expect.equal "Expecting an OBJECT with a field named `this-field-doesn't-exist`"

                    _ ->
                        Expect.fail ("Expected BadStatus, got: " ++ Debug.toString result)
            )
    , BackendTask.Http.getWithOptions
        { url = "https://api.github.com/repos/dillonkearns/elm-pages"
        , headers = []
        , cacheStrategy = Just BackendTask.Http.IgnoreCache
        , cachePath = Nothing
        , retries = Nothing
        , timeoutInMs = Nothing
        , expect =
            BackendTask.Http.expectJson
                (Decode.field "this-field-doesn't-exist" Decode.int)
        }
        |> BackendTask.mapError .recoverable
        |> test "cache options"
            (\result ->
                case result of
                    Err (BackendTask.Http.BadBody (Just (Decode.Failure failureString _)) _) ->
                        failureString
                            |> Expect.equal "Expecting an OBJECT with a field named `this-field-doesn't-exist`"

                    _ ->
                        Expect.fail ("Expected BadStatus, got: " ++ Debug.toString result)
            )
    , BackendTask.Http.getWithOptions
        { url = "https://api.github.com/repos/dillonkearns/elm-pages"
        , headers = []
        , cacheStrategy = Just BackendTask.Http.ForceRevalidate
        , cachePath = Nothing
        , retries = Nothing
        , timeoutInMs = Nothing
        , expect =
            BackendTask.Http.withMetadata Tuple.pair
                (BackendTask.Http.expectJson
                    (Decode.field "stargazers_count" Decode.int)
                )
        }
        |> test "with metadata"
            (\result ->
                case result of
                    Ok ( metadata, stars ) ->
                        metadata.statusCode
                            |> Expect.equal 200

                    _ ->
                        Expect.fail ("Expected Ok, got: " ++ Debug.toString result)
            )
    ]
        |> BackendTask.combine
        |> BackendTask.map (Test.describe "BackendTask tests")


test : String -> (Result error data -> Expect.Expectation) -> BackendTask error data -> BackendTask noError Test
test name assert task =
    task
        |> BackendTask.toResult
        |> BackendTask.map
            (\result ->
                Test.test name <|
                    \() ->
                        assert result
            )
