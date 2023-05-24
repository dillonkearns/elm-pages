module SetCookieTest exposing (all)

import Expect
import FatalError
import Server.SetCookie exposing (..)
import Test exposing (Test, describe, test)
import Time


all : Test
all =
    describe "SetCookie"
        [ test "simple value" <|
            \() ->
                options
                    |> nonSecure
                    |> withoutPath
                    |> makeVisibleToJavaScript
                    |> setCookie "sessionId" "38afes7a8"
                    |> toString
                    |> Expect.equal "sessionId=38afes7a8"
        , test "with expiration" <|
            \() ->
                options
                    |> nonSecure
                    |> withoutPath
                    |> withExpiration (Time.millisToPosix 1445412480000)
                    |> makeVisibleToJavaScript
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Wed, 21 Oct 2015 07:28:00 GMT"
        , test "http-only, multiple values" <|
            \() ->
                options
                    |> withoutPath
                    |> nonSecure
                    |> withExpiration (Time.millisToPosix 1445412480000)
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Wed, 21 Oct 2015 07:28:00 GMT; HttpOnly"
        , test "immediate expiration" <|
            \() ->
                options
                    |> nonSecure
                    |> withoutPath
                    |> withImmediateExpiration
                    |> makeVisibleToJavaScript
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
        , test "with path" <|
            \() ->
                options
                    |> nonSecure
                    |> withPath "/"
                    |> makeVisibleToJavaScript
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Path=/"
        , test "with max-age" <|
            \() ->
                options
                    |> nonSecure
                    |> withMaxAge 123
                    |> makeVisibleToJavaScript
                    |> withoutPath
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Max-Age=123"
        , test "encodes values" <|
            \() ->
                options
                    |> nonSecure
                    |> withoutPath
                    |> makeVisibleToJavaScript
                    |> setCookie "id" "This needs encoding & it uses url encoding"
                    |> toString
                    |> Expect.equal "id=This%20needs%20encoding%20%26%20it%20uses%20url%20encoding"
        , test "with domain" <|
            \() ->
                options
                    |> nonSecure
                    |> withoutPath
                    |> withDomain "example.com"
                    |> makeVisibleToJavaScript
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Domain=example.com"
        , test "secure" <|
            \() ->
                options
                    |> makeVisibleToJavaScript
                    |> withoutPath
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Secure"
        , test "SameSite" <|
            \() ->
                options
                    |> nonSecure
                    |> withSameSite Strict
                    |> withoutPath
                    |> makeVisibleToJavaScript
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; SameSite=Strict"
        ]
