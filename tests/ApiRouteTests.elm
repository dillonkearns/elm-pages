module ApiRouteTests exposing (all)

import ApiRoute exposing (..)
import DataSource
import Expect
import Internal.ApiRoute exposing (tryMatch, withRoutes)
import Pattern exposing (Pattern(..))
import Test exposing (Test, describe, test)


all : Test
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
        , describe "toPattern"
            [ test "no dynamic segments" <|
                \() ->
                    succeed
                        (DataSource.succeed { body = "" })
                        |> literal "no-dynamic-segments.json"
                        |> ApiRoute.singleServerless
                        |> Internal.ApiRoute.toPattern
                        |> Expect.equal (Pattern [ Pattern.Literal "no-dynamic-segments.json" ] Pattern.NoPendingSlash)
            , test "two literal segments" <|
                \() ->
                    ApiRoute.succeed (DataSource.succeed { body = "" })
                        |> ApiRoute.literal "api"
                        |> ApiRoute.slash
                        |> ApiRoute.literal "stars"
                        |> ApiRoute.singleServerless
                        |> Internal.ApiRoute.toPattern
                        |> Expect.equal
                            (Pattern
                                [ Pattern.Literal "api"
                                , Pattern.Literal "stars"
                                ]
                                Pattern.NoPendingSlash
                            )
            , test "routes to patterns" <|
                \() ->
                    succeed
                        (\userId ->
                            DataSource.succeed { body = "Data for user " ++ userId }
                        )
                        |> literal "users"
                        |> slash
                        |> capture
                        |> literal ".json"
                        |> buildTimeRoutes
                            (\route ->
                                DataSource.succeed
                                    [ route "100"
                                    , route "101"
                                    ]
                            )
                        |> Internal.ApiRoute.toPattern
                        |> Expect.equal
                            (Pattern
                                [ Pattern.Literal "users"
                                , Pattern.HybridSegment
                                    ( Pattern.Dynamic
                                    , Pattern.Literal ".json"
                                    , []
                                    )
                                ]
                                Pattern.NoPendingSlash
                            )
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
