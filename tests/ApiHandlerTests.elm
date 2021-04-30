module ApiHandlerTests exposing (..)

import ApiHandler exposing (..)
import Expect
import Test exposing (describe, only, test)


all =
    describe "api routes"
        [ test "match top-level file with no extension" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    (\_ -> [])
                    |> captureSegment
                    |> tryMatch "123"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "file with extension" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    (\_ -> [])
                    |> captureSegment
                    |> literalSegment ".json"
                    |> tryMatch "124.json"
                    |> Expect.equal (Just { body = "Data for user 124" })
        , test "file path with multiple segments" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    (\_ -> [])
                    |> literalSegment "users"
                    |> slash
                    |> captureSegment
                    |> literalSegment ".json"
                    |> tryMatch "users/123.json"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "routes" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    (\constructor ->
                        [ constructor "100"
                        , constructor "101"
                        ]
                    )
                    |> literalSegment "users"
                    |> slash
                    |> captureSegment
                    |> literalSegment ".json"
                    |> withRoutes
                    |> Expect.equal
                        [ "users/100.json"
                        , "users/101.json"
                        ]
        ]
