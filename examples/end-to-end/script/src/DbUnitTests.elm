module DbUnitTests exposing (run)

{-| Unit tests for the DB virtual layer using the real generated Pages.Db.testConfig.

Run with: cd examples/end-to-end && node ../../generator/src/cli.js run script/src/DbUnitTests.elm

Exercises the full Wire3 round-trip: encode → store → read → decode.

-}

import BackendTask exposing (BackendTask)
import Db
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Pages.Db
import Pages.Script as Script exposing (Script)
import Test.BackendTask as BackendTaskTest
import Test.Runner


run : Script
run =
    Script.withoutCliOptions
        (test "get returns seeded value"
            (Pages.Db.get Pages.Db.default
                |> BackendTask.andThen
                    (\db ->
                        Script.log ("nextId=" ++ String.fromInt db.nextId)
                    )
                |> BackendTaskTest.fromBackendTaskWithDb Pages.Db.testConfig
                    { todos = [], nextId = 42 }
                |> BackendTaskTest.ensureLogged "nextId=42"
                |> BackendTaskTest.expectSuccess
            )
            |> BackendTask.andThen
                (\_ ->
                    test "update persists and round-trips through Wire3"
                        (Pages.Db.update Pages.Db.default
                            (\db -> { db | nextId = db.nextId + 1 })
                            |> BackendTaskTest.fromBackendTaskWithDb Pages.Db.testConfig
                                { todos = [], nextId = 10 }
                            |> BackendTaskTest.expectDb Pages.Db.testConfig
                                (\db -> Expect.equal 11 db.nextId)
                        )
                )
            |> BackendTask.andThen
                (\_ ->
                    test "two consecutive updates accumulate"
                        (Pages.Db.update Pages.Db.default
                            (\db -> { db | nextId = db.nextId + 1 })
                            |> BackendTask.andThen
                                (\() ->
                                    Pages.Db.update Pages.Db.default
                                        (\db -> { db | nextId = db.nextId * 10 })
                                )
                            |> BackendTaskTest.fromBackendTaskWithDb Pages.Db.testConfig
                                { todos = [], nextId = 5 }
                            |> BackendTaskTest.expectDb Pages.Db.testConfig
                                (\db -> Expect.equal 60 db.nextId)
                        )
                )
            |> BackendTask.andThen
                (\_ ->
                    test "update with todos round-trips through Wire3"
                        (Pages.Db.update Pages.Db.default
                            (\db ->
                                { db
                                    | todos =
                                        db.todos
                                            ++ [ { id = db.nextId, title = "New todo", completed = False } ]
                                    , nextId = db.nextId + 1
                                }
                            )
                            |> BackendTaskTest.fromBackendTaskWithDb Pages.Db.testConfig
                                { todos = [ { id = 1, title = "First", completed = True } ]
                                , nextId = 2
                                }
                            |> BackendTaskTest.expectDb Pages.Db.testConfig
                                (\db ->
                                    Expect.all
                                        [ \d -> Expect.equal 2 (List.length d.todos)
                                        , \d -> Expect.equal 3 d.nextId
                                        , \d ->
                                            d.todos
                                                |> List.map .title
                                                |> Expect.equal [ "First", "New todo" ]
                                        ]
                                        db
                                )
                        )
                )
            |> BackendTask.andThen
                (\_ ->
                    test "transaction returns value and persists"
                        (Pages.Db.transaction Pages.Db.default
                            (\db ->
                                BackendTask.succeed
                                    ( { db | nextId = db.nextId + 1 }
                                    , List.length db.todos
                                    )
                            )
                            |> BackendTask.andThen
                                (\count ->
                                    Script.log ("count=" ++ String.fromInt count)
                                )
                            |> BackendTaskTest.fromBackendTaskWithDb Pages.Db.testConfig
                                { todos = [ { id = 1, title = "A", completed = False } ], nextId = 2 }
                            |> BackendTaskTest.ensureLogged "count=1"
                            |> BackendTaskTest.expectDb Pages.Db.testConfig
                                (\db -> Expect.equal 3 db.nextId)
                        )
                )
            |> BackendTask.andThen
                (\_ -> Script.log "\n=== All DB unit tests passed! ===")
        )


test : String -> Expectation -> BackendTask FatalError ()
test label expectation =
    case Test.Runner.getFailureReason expectation of
        Nothing ->
            Script.log ("  PASS: " ++ label)

        Just failure ->
            BackendTask.fail
                (FatalError.build
                    { title = "FAIL: " ++ label
                    , body = failure.description
                    }
                )
