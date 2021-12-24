module SetCookieTest exposing (all)

import Expect
import Server.SetCookie as SetCookie exposing (..)
import Test exposing (Test, describe, test)
import Time


all : Test
all =
    describe "SetCookie"
        [ test "simple value" <|
            \() ->
                setCookie "sessionId" "38afes7a8"
                    |> nonSecure
                    |> toString
                    |> Expect.equal "sessionId=38afes7a8"
        , test "with expiration" <|
            \() ->
                setCookie "id" "a3fWa"
                    |> nonSecure
                    |> withExpiration (Time.millisToPosix 1445412480000)
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Wed, 21 Oct 2015 07:28:00 GMT"
        , test "http-only, multiple values" <|
            \() ->
                setCookie "id" "a3fWa"
                    |> nonSecure
                    |> withExpiration (Time.millisToPosix 1445412480000)
                    |> httpOnly
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Wed, 21 Oct 2015 07:28:00 GMT; HttpOnly"
        , test "immediate expiration" <|
            \() ->
                setCookie "id" "a3fWa"
                    |> nonSecure
                    |> withImmediateExpiration
                    |> toString
                    |> Expect.equal "id=a3fWa; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
        , test "with path" <|
            \() ->
                setCookie "id" "a3fWa"
                    |> nonSecure
                    |> withPath "/"
                    |> toString
                    |> Expect.equal "id=a3fWa; Path=/"
        , test "with max-age" <|
            \() ->
                setCookie "id" "a3fWa"
                    |> nonSecure
                    |> withMaxAge 123
                    |> toString
                    |> Expect.equal "id=a3fWa; Max-Age=123"
        , test "encodes values" <|
            \() ->
                setCookie "id" "This needs encoding & it uses url encoding"
                    |> nonSecure
                    |> toString
                    |> Expect.equal "id=This%20needs%20encoding%20%26%20it%20uses%20url%20encoding"
        , test "with domain" <|
            \() ->
                setCookie "id" "a3fWa"
                    |> nonSecure
                    |> withDomain "example.com"
                    |> toString
                    |> Expect.equal "id=a3fWa; Domain=example.com"
        , test "secure" <|
            \() ->
                setCookie "id" "a3fWa"
                    |> toString
                    |> Expect.equal "id=a3fWa; Secure"
        , test "SameSite" <|
            \() ->
                setCookie "id" "a3fWa"
                    |> nonSecure
                    |> withSameSite SetCookie.Strict
                    |> toString
                    |> Expect.equal "id=a3fWa; SameSite=Strict"
        ]
