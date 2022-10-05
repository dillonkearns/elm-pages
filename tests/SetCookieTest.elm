module SetCookieTest exposing (all)

import Expect
import Server.SetCookie exposing (..)
import Test exposing (Test, describe, test)
import Time


all : Test
all =
    describe "SetCookie"
        [ test "simple value" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> setCookie "sessionId" "38afes7a8"
                    |> toString
                    |> Expect.equal "sessionId=38afes7a8"
        , test "with expiration" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> withExpiration (Time.millisToPosix 1445412480000)
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Wed, 21 Oct 2015 07:28:00 GMT"
        , test "http-only, multiple values" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> withExpiration (Time.millisToPosix 1445412480000)
                    |> httpOnly
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Wed, 21 Oct 2015 07:28:00 GMT; HttpOnly"
        , test "immediate expiration" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> withImmediateExpiration
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
        , test "with path" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> withPath "/"
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Path=/"
        , test "with max-age" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> withMaxAge 123
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Max-Age=123"
        , test "encodes values" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> setCookie "id" "This needs encoding & it uses url encoding"
                    |> toString
                    |> Expect.equal "id=This%20needs%20encoding%20%26%20it%20uses%20url%20encoding"
        , test "with domain" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> withDomain "example.com"
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Domain=example.com"
        , test "secure" <|
            \() ->
                initOptions
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Secure"
        , test "SameSite" <|
            \() ->
                initOptions
                    |> nonSecure
                    |> withSameSite Strict
                    |> setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; SameSite=Strict"
        ]
