module SessionSigningTests exposing (all)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import Expect
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Test.BackendTask.Internal as TestInternal
import Test.PagesProgram.CookieJar as CookieJar
import Test.PagesProgram.Session as Session


all : Test
all =
    describe "Session signing envelope"
        [ describe "mockSignValue / mockUnsignValue round-trip"
            [ test "preserves secret and values" <|
                \() ->
                    let
                        values =
                            Encode.object [ ( "userId", Encode.string "42" ) ]
                    in
                    TestInternal.mockSignValue "test-secret" values
                        |> TestInternal.mockUnsignValue
                        |> Maybe.map (\r -> ( r.secret, Encode.encode 0 r.values ))
                        |> Expect.equal (Just ( "test-secret", "{\"userId\":\"42\"}" ))
            , test "different secrets produce different checksums" <|
                \() ->
                    let
                        values =
                            Encode.object [ ( "a", Encode.int 1 ) ]
                    in
                    Expect.notEqual
                        (TestInternal.mockSignValue "secret-a" values)
                        (TestInternal.mockSignValue "secret-b" values)
            , test "round-trips values containing dots (floats)" <|
                \() ->
                    let
                        values =
                            Encode.object [ ( "pi", Encode.float 3.14 ) ]

                        signed =
                            TestInternal.mockSignValue "rotating-key" values
                    in
                    signed
                        |> TestInternal.mockUnsignValue
                        |> Maybe.map .secret
                        |> Expect.equal (Just "rotating-key")
            ]
        , describe "mockUnsignValue rejects non-signed input"
            [ test "plain string" <|
                \() ->
                    TestInternal.mockUnsignValue "plain-cookie"
                        |> Expect.equal Nothing
            , test "two-dot string without a numeric checksum segment" <|
                \() ->
                    TestInternal.mockUnsignValue "something.with.dots-but-no-digits"
                        |> Expect.equal Nothing
            , test "legacy \"****SIGNED****\" envelope no longer unsigns" <|
                \() ->
                    TestInternal.mockUnsignValue "****SIGNED****{\"old\":\"format\"}"
                        |> Expect.equal Nothing
            , test "empty secret segment" <|
                \() ->
                    -- "<json>..<checksum>" with empty middle
                    TestInternal.mockUnsignValue "{\"a\":1}..123"
                        |> Expect.equal Nothing
            , test "tampered checksum makes mockUnsignValue fail" <|
                \() ->
                    let
                        signed =
                            TestInternal.mockSignValue "s"
                                (Encode.object [ ( "k", Encode.string "v" ) ])

                        tampered =
                            -- replace the checksum segment with a bogus but
                            -- still-all-digits value
                            case String.indexes "." signed |> List.reverse |> List.head of
                                Just idx ->
                                    String.left idx signed ++ ".999999"

                                Nothing ->
                                    signed
                    in
                    TestInternal.mockUnsignValue tampered
                        |> Expect.equal Nothing
            , test "tampered JSON payload (same length) makes mockUnsignValue fail" <|
                \() ->
                    let
                        -- two-char value so the tampered string has the same
                        -- length as the original and we only perturb the JSON
                        signed =
                            TestInternal.mockSignValue "s"
                                (Encode.object [ ( "k", Encode.string "ab" ) ])

                        tampered =
                            String.replace "\"ab\"" "\"xy\"" signed
                    in
                    TestInternal.mockUnsignValue tampered
                        |> Expect.equal Nothing
            ]
        , describe "encrypt/decrypt BackendTask intercepts"
            -- Exercise the full production path used by Server.Session.sign/unsign:
            -- craft the same BackendTask requests Server.Session issues, and run
            -- them through the Test.BackendTask harness which intercepts them in
            -- Test.BackendTask.Internal and routes to mockSignValue/mockUnsignValue.
            [ test "same secret: encrypt then decrypt recovers the payload" <|
                \() ->
                    let
                        payload =
                            Encode.object
                                [ ( "userId", Encode.string "42" )
                                , ( "role", Encode.string "admin" )
                                ]
                    in
                    signBackendTask "secret-one" payload
                        |> BackendTask.andThen (unsignBackendTask [ "secret-one" ])
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccessWith
                            (\decoded ->
                                Expect.equal
                                    (Encode.encode 0 decoded)
                                    (Encode.encode 0 payload)
                            )
            , test "mismatched secret: decrypt returns null" <|
                -- Matches production behavior (cookie-signature's unsign
                -- returns false when no secret verifies).
                \() ->
                    let
                        payload =
                            Encode.object [ ( "marker", Encode.string "hello" ) ]
                    in
                    signBackendTask "real-secret" payload
                        |> BackendTask.andThen (unsignBackendTask [ "wrong-secret-one", "wrong-secret-two" ])
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccessWith
                            (\decoded ->
                                Expect.equal (Encode.encode 0 decoded) "null"
                            )
            , test "secret rotation: decrypt succeeds when the list contains the embedded secret" <|
                \() ->
                    let
                        payload =
                            Encode.object [ ( "rotated", Encode.string "yes" ) ]
                    in
                    signBackendTask "old-secret" payload
                        |> BackendTask.andThen (unsignBackendTask [ "new-secret", "old-secret" ])
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccessWith
                            (\decoded ->
                                Expect.equal
                                    (Encode.encode 0 decoded)
                                    (Encode.encode 0 payload)
                            )
            , test "tampered JSON: decrypt returns null" <|
                \() ->
                    let
                        payload =
                            Encode.object [ ( "role", Encode.string "user" ) ]
                    in
                    signBackendTask "s" payload
                        |> BackendTask.map (String.replace "\"user\"" "\"root\"")
                        |> BackendTask.andThen (unsignBackendTask [ "s" ])
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccessWith
                            (\decoded ->
                                Expect.equal (Encode.encode 0 decoded) "null"
                            )
            , test "decrypt on a plain (unsigned) cookie returns null" <|
                \() ->
                    unsignBackendTask [ "any-secret" ] "not-a-signed-cookie"
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccessWith
                            (\decoded ->
                                Expect.equal (Encode.encode 0 decoded) "null"
                            )
            , test "empty secrets list: decrypt returns null" <|
                \() ->
                    let
                        payload =
                            Encode.object [ ( "marker", Encode.string "hello" ) ]
                    in
                    signBackendTask "any" payload
                        |> BackendTask.andThen (unsignBackendTask [])
                        |> BackendTaskTest.fromBackendTask
                        |> BackendTaskTest.expectSuccessWith
                            (\decoded ->
                                Expect.equal (Encode.encode 0 decoded) "null"
                            )
            ]
        , describe "multiple differently-named sessions"
            -- Tests confirm sessions with different cookie names don't clash:
            -- each lives under its own name in the jar, each carries its own
            -- secret, and unsigning one cannot accidentally pick up the other.
            [ test "two sessions with different names + secrets coexist in the jar" <|
                \() ->
                    let
                        jar =
                            CookieJar.init
                                |> CookieJar.setSession
                                    { name = "user_session"
                                    , secret = "user-secret"
                                    , session =
                                        Session.init
                                            |> Session.withValue "userId" "1"
                                    }
                                |> CookieJar.setSession
                                    { name = "admin_session"
                                    , secret = "admin-secret"
                                    , session =
                                        Session.init
                                            |> Session.withValue "adminId" "99"
                                    }

                        userResult =
                            CookieJar.get "user_session" jar
                                |> Maybe.andThen TestInternal.mockUnsignValue
                                |> Maybe.map (\r -> ( r.secret, Encode.encode 0 r.values ))

                        adminResult =
                            CookieJar.get "admin_session" jar
                                |> Maybe.andThen TestInternal.mockUnsignValue
                                |> Maybe.map (\r -> ( r.secret, Encode.encode 0 r.values ))
                    in
                    Expect.all
                        [ \_ ->
                            userResult
                                |> Expect.equal (Just ( "user-secret", "{\"userId\":\"1\"}" ))
                        , \_ ->
                            adminResult
                                |> Expect.equal (Just ( "admin-secret", "{\"adminId\":\"99\"}" ))
                        ]
                        ()
            , test "reading a non-existent session name returns Nothing" <|
                \() ->
                    CookieJar.init
                        |> CookieJar.setSession
                            { name = "mysession"
                            , secret = "s"
                            , session = Session.init |> Session.withValue "k" "v"
                            }
                        |> CookieJar.get "some_other_name"
                        |> Expect.equal Nothing
            , test "same name with a later setSession overwrites the earlier one" <|
                \() ->
                    let
                        signedAfter =
                            CookieJar.init
                                |> CookieJar.setSession
                                    { name = "mysession"
                                    , secret = "s1"
                                    , session = Session.init |> Session.withValue "v" "old"
                                    }
                                |> CookieJar.setSession
                                    { name = "mysession"
                                    , secret = "s2"
                                    , session = Session.init |> Session.withValue "v" "new"
                                    }
                                |> CookieJar.get "mysession"
                                |> Maybe.andThen TestInternal.mockUnsignValue
                    in
                    signedAfter
                        |> Maybe.map (\r -> ( r.secret, Encode.encode 0 r.values ))
                        |> Expect.equal (Just ( "s2", "{\"v\":\"new\"}" ))
            ]
        ]



-- Replicas of Server.Session.sign / Server.Session.unsign, scoped to the test.
-- We can't import them directly (Server.Session exposes only the high-level
-- withSession), but we replicate the exact BackendTask requests the real
-- implementation issues so the Test.BackendTask harness exercises the real
-- encrypt/decrypt intercept.


signBackendTask : String -> Encode.Value -> BackendTask FatalError String
signBackendTask secret values =
    BackendTask.Internal.Request.request
        { name = "encrypt"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "values", values )
                    , ( "secret", Encode.string secret )
                    ]
                )
        , expect = Decode.string
        }


unsignBackendTask : List String -> String -> BackendTask FatalError Encode.Value
unsignBackendTask secrets input =
    BackendTask.Internal.Request.request
        { name = "decrypt"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "input", Encode.string input )
                    , ( "secrets", Encode.list Encode.string secrets )
                    ]
                )
        , expect = Decode.value
        }
