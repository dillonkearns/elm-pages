module ApiRouteTests exposing (..)

import ApiRoute exposing (..)
import Expect
import Test exposing (describe, test)


all =
    describe "api routes"
        [ test "match top-level file with no extension" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> capture
                    |> tryMatch "123"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "file with extension" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> capture
                    |> literal ".json"
                    |> tryMatch "124.json"
                    |> Expect.equal (Just { body = "Data for user 124" })
        , test "file path with multiple segments" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> literal "users"
                    |> slash
                    |> capture
                    |> literal ".json"
                    |> tryMatch "users/123.json"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "integer matcher" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ String.fromInt userId }
                    )
                    |> literal "users"
                    |> slash
                    |> int
                    |> literal ".json"
                    |> tryMatch "users/123.json"
                    |> Expect.equal (Just { body = "Data for user 123" })
        , test "routes" <|
            \() ->
                succeed
                    (\userId ->
                        { body = "Data for user " ++ userId }
                    )
                    |> literal "users"
                    |> slash
                    |> capture
                    |> literal ".json"
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
                        (\_ _ ->
                            { body = "Data for user" }
                        )
                        |> literal "repos"
                        |> slash
                        |> capture
                        |> slash
                        |> capture
                        |> literal ".json"
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
                        |> literal "repos"
                        |> slash
                        |> capture
                        |> slash
                        |> capture
                        |> slash
                        |> capture
                        |> withRoutes
                            (\constructor ->
                                [ constructor "dillonkearns" "elm-pages" "static-files" ]
                            )
                        |> Expect.equal
                            [ "repos/dillonkearns/elm-pages/static-files" ]
            ]
        ]
