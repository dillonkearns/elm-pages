module ApiHandlerTests exposing (..)

import ApiHandler exposing (..)
import Expect
import Test exposing (describe, only, test)


all =
    describe "api routes"
        [ -- test "match top-level file with no extension" <|
          --    \() ->
          --        succeed
          --            (\userId ->
          --                { body = "Data for user " ++ userId }
          --            )
          --            (\_ -> [])
          --            |> captureSegment
          --            |> tryMatch "123"
          --            |> Expect.equal (Just { body = "Data for user 123" })
          --, test "file with extension" <|
          --    \() ->
          --        succeed
          --            (\userId ->
          --                { body = "Data for user " ++ userId }
          --            )
          --            (\_ -> [])
          --            |> captureSegment
          --            |> literalSegment ".json"
          --            |> tryMatch "124.json"
          --            |> Expect.equal (Just { body = "Data for user 124" })
          --, test "file path with multiple segments" <|
          --    \() ->
          --        succeed
          --            (\userId ->
          --                { body = "Data for user " ++ userId }
          --            )
          --            (\_ -> [])
          --            |> literalSegment "users"
          --            |> slash
          --            |> captureSegment
          --            |> literalSegment ".json"
          --            |> tryMatch "users/123.json"
          --            |> Expect.equal (Just { body = "Data for user 123" })
          --, test "routes" <|
          --    \() ->
          --        succeed
          --            (\userId ->
          --                { body = "Data for user " ++ userId }
          --            )
          --            (\constructor ->
          --                [ constructor "100"
          --                , constructor "101"
          --                ]
          --            )
          --            |> literalSegment "users"
          --            |> slash
          --            |> captureSegment
          --            |> literalSegment ".json"
          --            |> withRoutes
          --            |> Expect.equal
          --                [ "users/100.json"
          --                , "users/101.json"
          --                ],
          only <|
            describe "multi-part"
                [ --test "multi-level routes" <|
                  --    \() ->
                  --        newThing
                  --            |> withRoutes
                  --            |> Expect.equal
                  --                [ "repos/dillonkearns/elm-pages.json"
                  --
                  --                --, "users/101.json"
                  --                ],
                  test "3-level route" <|
                    \() ->
                        threeParts
                            |> withRoutes
                                (\constructor ->
                                    [ constructor "dillonkearns" "elm-pages" "static-files"
                                    ]
                                )
                            |> Expect.equal
                                [ "repos/dillonkearns/elm-pages.json"

                                --, "users/101.json"
                                ]
                ]
        ]


newThing : Handler { body : String } (String -> String -> String)
newThing =
    succeedNew
        (\userName repoName ->
            { body = "Data for user" }
        )
        --(Debug.todo "")
        --(\a ->
        --    [ --constructor "dillonkearns" "elm-pages"
        --      --, constructor "101"
        --      a "dillonkearns" "elm-pages" -- [ "1", "2" ]
        --
        --    --, constructor "elm-pages"
        --    ]
        --)
        --(Debug.todo "")
        |> literalSegment "repos"
        |> slash
        |> captureNew
        |> slash
        |> captureNew


threeParts : Handler { body : String } (String -> String -> String -> String)
threeParts =
    succeedNew
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
