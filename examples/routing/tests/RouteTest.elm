module RouteTest exposing (..)

import Expect
import Route
import Test exposing (Test, describe, test)


all : Test
all =
    describe "routes"
        [ test "test 1" <|
            \() ->
                --{ path = "/cats/larry" }
                --{ path = "/slide" }
                { path = "/cats/larry" }
                    |> Route.urlToRoute
                    |> Expect.equal
                        (Route.Cats__Name__
                            { name = Just "larry" }
                            |> Just
                        )

        --, test "test 2" <|
        --    \() ->
        --        "/cats"
        --            |> tryMatch
        --                { pattern = "^cats(?:\\/([^/]+))?$"
        --                , toRoute =
        --                    \matches ->
        --                        case matches of
        --                            [ name ] ->
        --                                Cats__Name__ { name = name } |> Just
        --
        --                            _ ->
        --                                Nothing
        --                }
        --            |> Expect.equal (Cats__Name__ { name = Nothing } |> Just)
        --, test "multiple matchers" <|
        --    \() ->
        --        "/slide/123"
        --            |> firstMatch exampleMatchers
        --            |> Expect.equal (Slide__Number_ { number = "123" } |> Just)
        --, test "hardcoded routes have precedence over dynamic segments" <|
        --    \() ->
        --        "/post/create"
        --            |> firstMatch postPrecedenceExample
        --            |> Expect.equal (Post__Create {} |> Just)
        --, test "dynamic segments match when they are not overshadowed by a hardcoded route" <|
        --    \() ->
        --        "/post/update"
        --            |> firstMatch postPrecedenceExample
        --            |> Expect.equal (Post__Slug_ { slug = "update" } |> Just)
        ]
