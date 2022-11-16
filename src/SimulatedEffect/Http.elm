module SimulatedEffect.Http exposing
    ( get, post, request
    , Header, header
    , Body, emptyBody, stringBody, jsonBody
    , Expect, expectString, expectJson, expectWhatever, Error
    , expectStringResponse, Response
    , task, Resolver, stringResolver
    )

{-| This module parallels [elm/http's `Http` module](https://package.elm-lang.org/packages/elm/http/2.0.0/Http).
_Pull requests are welcome to add any functions that are missing._

The functions here produce `SimulatedEffect`s instead of `Cmd`s, which are meant to be used
to help you implement the function to provide when using [`ProgramTest.withSimulatedEffects`](ProgramTest#withSimulatedEffects).


# Requests

@docs get, post, request


# Header

@docs Header, header


# Body

@docs Body, emptyBody, stringBody, jsonBody


# Expect

@docs Expect, expectString, expectJson, expectWhatever, Error


# Elaborate Expectations

@docs expectStringResponse, Response


# Tasks

@docs task, Resolver, stringResolver

-}

import Http
import Json.Decode exposing (Decoder)
import Json.Encode
import ProgramTest exposing (SimulatedEffect, SimulatedTask)
import SimulatedEffect


{-| Create a `GET` request.
-}
get :
    { url : String
    , expect : Expect msg
    }
    -> SimulatedEffect msg
get r =
    request
        { method = "GET"
        , headers = []
        , url = r.url
        , body = emptyBody
        , expect = r.expect
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Create a `POST` request.
-}
post :
    { url : String
    , body : Body
    , expect : Expect msg
    }
    -> SimulatedEffect msg
post r =
    request
        { method = "POST"
        , headers = []
        , url = r.url
        , body = r.body
        , expect = r.expect
        , timeout = Nothing
        , tracker = Nothing
        }


{-| Create a custom request.
-}
request :
    { method : String
    , headers : List Header
    , url : String
    , body : Body
    , expect : Expect msg
    , timeout : Maybe Float
    , tracker : Maybe String
    }
    -> SimulatedEffect msg
request r =
    let
        (Expect onResult) =
            r.expect
    in
    SimulatedEffect.HttpTask
        { method = r.method
        , url = r.url
        , headers =
            case r.body of
                EmptyBody ->
                    r.headers

                StringBody body ->
                    header "Content-Type" body.contentType :: r.headers
        , body =
            case r.body of
                EmptyBody ->
                    ""

                StringBody body ->
                    body.content
        , onRequestComplete = onResult >> SimulatedEffect.Succeed
        }
        |> SimulatedEffect.Task


{-| An HTTP header for configuring requests.
-}
type alias Header =
    ( String, String )


{-| Create a `Header`.
-}
header : String -> String -> Header
header =
    Tuple.pair


{-| Represents the body of a `Request`.
-}
type Body
    = EmptyBody
    | StringBody
        { contentType : String
        , content : String
        }


{-| Create an empty body for your `Request`.
-}
emptyBody : Body
emptyBody =
    EmptyBody


{-| Put some JSON value in the body of your `Request`. This will automatically
add the `Content-Type: application/json` header.
-}
jsonBody : Json.Encode.Value -> Body
jsonBody value =
    StringBody
        { contentType = "application/json"
        , content = Json.Encode.encode 0 value
        }


{-| Put some string in the body of your `Request`.
-}
stringBody : String -> String -> Body
stringBody contentType content =
    StringBody
        { contentType = contentType
        , content = content
        }


{-| Logic for interpreting a response body.
-}
type Expect msg
    = Expect (Http.Response String -> msg)


{-| Expect the response body to be a `String`.
-}
expectString : (Result Http.Error String -> msg) -> Expect msg
expectString onResult =
    Expect <|
        \response ->
            case response of
                Http.BadUrl_ s ->
                    onResult (Err <| Http.BadUrl s)

                Http.Timeout_ ->
                    onResult (Err Http.Timeout)

                Http.NetworkError_ ->
                    onResult (Err Http.NetworkError)

                Http.BadStatus_ metadata body ->
                    onResult (Err <| Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ _ body ->
                    onResult (Ok body)


{-| Expect a Response with a String body.
-}
expectStringResponse : (Result x a -> msg) -> (Response String -> Result x a) -> Expect msg
expectStringResponse toMsg onResponse =
    Expect (onResponse >> toMsg)


{-| Expect the response body to be JSON.
-}
expectJson : (Result Http.Error a -> msg) -> Decoder a -> Expect msg
expectJson onResult decoder =
    Expect <|
        \response ->
            case response of
                Http.BadUrl_ s ->
                    onResult (Err <| Http.BadUrl s)

                Http.Timeout_ ->
                    onResult (Err Http.Timeout)

                Http.NetworkError_ ->
                    onResult (Err Http.NetworkError)

                Http.BadStatus_ metadata _ ->
                    onResult (Err <| Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ _ body ->
                    case Json.Decode.decodeString decoder body of
                        Err jsonError ->
                            onResult (Err <| Http.BadBody <| Json.Decode.errorToString jsonError)

                        Ok value ->
                            onResult (Ok value)


{-| Expect the response body to be whatever.
-}
expectWhatever : (Result Error () -> msg) -> Expect msg
expectWhatever onResult =
    Expect <|
        \response ->
            case response of
                Http.BadUrl_ s ->
                    onResult (Err <| Http.BadUrl s)

                Http.Timeout_ ->
                    onResult (Err Http.Timeout)

                Http.NetworkError_ ->
                    onResult (Err Http.NetworkError)

                Http.BadStatus_ metadata _ ->
                    onResult (Err <| Http.BadStatus metadata.statusCode)

                Http.GoodStatus_ _ _ ->
                    onResult (Ok ())


{-| -}
type alias Error =
    Http.Error


{-| -}
type alias Response body =
    Http.Response body


{-| Just like [`request`](#request), but it creates a `Task`.
-}
task :
    { method : String
    , headers : List Header
    , url : String
    , body : Body
    , resolver : Resolver x a
    , timeout : Maybe Float
    }
    -> SimulatedTask x a
task r =
    SimulatedEffect.HttpTask
        { method = r.method
        , url = r.url
        , headers = r.headers
        , body =
            case r.body of
                EmptyBody ->
                    ""

                StringBody body ->
                    body.content
        , onRequestComplete =
            case r.resolver of
                StringResolver f ->
                    f
        }


{-| Describes how to resolve an HTTP task.
-}
type Resolver x a
    = StringResolver (Response String -> SimulatedTask x a)


{-| Turn a response with a `String` body into a result.
-}
stringResolver : (Response String -> Result x a) -> Resolver x a
stringResolver f =
    let
        fromResult result =
            case result of
                Err x ->
                    SimulatedEffect.Fail x

                Ok a ->
                    SimulatedEffect.Succeed a
    in
    StringResolver (f >> fromResult)
