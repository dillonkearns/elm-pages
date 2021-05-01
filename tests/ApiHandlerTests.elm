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
                    |> captureNew
                    |> tryMatch "123"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "file with extension" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> captureNew
                    |> literalSegment ".json"
                    |> tryMatch "124.json"
                    |> Expect.equal (Just { body = "Data for user 124" })
        , test "file path with multiple segments" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> literalSegment "users"
                    |> slash
                    |> captureNew
                    |> literalSegment ".json"
                    |> tryMatch "users/123.json"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "routes" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> literalSegment "users"
                    |> slash
                    |> captureNew
                    |> literalSegment ".json"
                    |> withRoutes
                        (\constructor ->
                            [ constructor "100"
                            , constructor "101"
                            ]
                        )
                    |> Expect.equal
                        [ "users/100.json"
                        , "users/101.json"
                        ]
        , describe "multi-part"
            [ test "multi-level routes" <|
                \() ->
                    succeed
                        (\userName repoName ->
                            { body = "Data for user" }
                        )
                        |> literalSegment "repos"
                        |> slash
                        |> captureNew
                        |> slash
                        |> captureNew
                        |> literalSegment ".json"
                        |> withRoutes
                            (\a ->
                                [ a "dillonkearns" "elm-pages"
                                , a "dillonkearns" "elm-markdown"
                                ]
                            )
                        |> Expect.equal
                            [ "repos/dillonkearns/elm-pages.json"
                            , "repos/dillonkearns/elm-markdown.json"
                            ]
            , test "3-level route" <|
                \() ->
                    succeed
                        (\username repo branch ->
                            { body = [ username, repo, branch ] |> String.join " - " }
                        )
                        |> literalSegment "repos"
                        |> slash
                        |> captureNew
                        |> slash
                        |> captureNew
                        |> slash
                        |> captureNew
                        |> withRoutes
                            (\constructor ->
                                [ constructor "dillonkearns" "elm-pages" "static-files" ]
                            )
                        |> Expect.equal
                            [ "repos/dillonkearns/elm-pages/static-files" ]
            ]
        ]
