module CookieJarTests exposing (all)

import Dict
import Expect
import Test exposing (Test, describe, test)
import Test.PagesProgram.CookieJar as CookieJar


all : Test
all =
    describe "Test.PagesProgram.CookieJar"
        [ describe "withSetCookieHeaders — attribute parsing"
            [ test "sid with Path, HttpOnly, Secure, SameSite" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders
                            [ "sid=abc; Path=/; HttpOnly; Secure; SameSite=Lax" ]
                        |> CookieJar.getEntry "sid"
                        |> Expect.equal
                            (Just
                                { value = "abc"
                                , path = Just "/"
                                , domain = Nothing
                                , expires = Nothing
                                , maxAge = Nothing
                                , secure = True
                                , httpOnly = True
                                , sameSite = Just "Lax"
                                }
                            )
            , test "theme=dark has all defaults" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders [ "theme=dark" ]
                        |> CookieJar.getEntry "theme"
                        |> Expect.equal
                            (Just
                                { value = "dark"
                                , path = Nothing
                                , domain = Nothing
                                , expires = Nothing
                                , maxAge = Nothing
                                , secure = False
                                , httpOnly = False
                                , sameSite = Nothing
                                }
                            )
            , test "Max-Age parsed as Int, Domain preserved" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders
                            [ "token=xyz; Max-Age=3600; Domain=.example.com" ]
                        |> CookieJar.getEntry "token"
                        |> Maybe.map (\e -> ( e.maxAge, e.domain ))
                        |> Expect.equal (Just ( Just 3600, Just ".example.com" ))
            , test "duplicate cookie header — second value wins" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders
                            [ "theme=light", "theme=dark" ]
                        |> CookieJar.get "theme"
                        |> Expect.equal (Just "dark")
            ]
        , describe "public API stability"
            [ test "toDict returns name/value pairs (drops attributes)" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.withSetCookieHeaders
                            [ "a=1; Path=/"
                            , "b=2; HttpOnly"
                            ]
                        |> CookieJar.toDict
                        |> Expect.equalDicts
                            (Dict.fromList [ ( "a", "1" ), ( "b", "2" ) ])
            , test "set builds a plain entry with default attributes" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.set "user" "alice"
                        |> CookieJar.getEntry "user"
                        |> Maybe.map (\e -> ( e.value, e.secure, e.httpOnly ))
                        |> Expect.equal (Just ( "alice", False, False ))
            ]
        ]
