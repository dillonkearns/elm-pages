module DbTests exposing (run)

{-| Integration tests for the Pages.Db built-in database.

Run with: cd examples/end-to-end && node ../../generator/src/cli.js run DbTests

Requires lamdera on PATH (for Wire3 codec generation).

-}

import BackendTask exposing (BackendTask)
import Db
import FatalError exposing (FatalError)
import Pages.Db
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (cleanup
            |> BackendTask.andThen (\_ -> runAllTests)
            |> BackendTask.finally cleanup
        )


runAllTests : BackendTask FatalError ()
runAllTests =
    testGetReturnsInitWhenNoDbBin
        |> BackendTask.andThen (\_ -> testUpdatePersistsData)
        |> BackendTask.andThen (\_ -> testGetReadsPersistedData)
        |> BackendTask.andThen (\_ -> testUpdateIsAdditive)
        |> BackendTask.andThen (\_ -> testTransactionReturnsValue)
        |> BackendTask.andThen (\_ -> Script.log "\n=== All Pages.Db tests passed! ===")



-- Test cases


{-| When no db.bin exists, get should return Db.init.
-}
testGetReturnsInitWhenNoDbBin : BackendTask FatalError ()
testGetReturnsInitWhenNoDbBin =
    Script.log "Test: get returns Db.init when no db.bin exists"
        |> BackendTask.andThen (\_ -> cleanup)
        |> BackendTask.andThen (\_ -> Pages.Db.get Pages.Db.default)
        |> BackendTask.andThen
            (\db ->
                if List.isEmpty db.todos && db.nextId == 1 then
                    pass "get returns init"

                else
                    fail "get returns init"
                        ("Expected { todos = [], nextId = 1 } but got { todos = "
                            ++ String.fromInt (List.length db.todos)
                            ++ " items, nextId = "
                            ++ String.fromInt db.nextId
                            ++ " }"
                        )
            )


{-| After update, the new data should be persisted.
-}
testUpdatePersistsData : BackendTask FatalError ()
testUpdatePersistsData =
    Script.log "Test: update persists data"
        |> BackendTask.andThen
            (\_ ->
                Pages.Db.update
                    Pages.Db.default
                    (\db ->
                        { db
                            | todos = [ { id = 1, title = "Test todo", completed = False } ]
                            , nextId = 2
                        }
                    )
            )
        |> BackendTask.andThen (\_ -> Pages.Db.get Pages.Db.default)
        |> BackendTask.andThen
            (\db ->
                case db.todos of
                    [ todo ] ->
                        if todo.id == 1 && todo.title == "Test todo" && not todo.completed && db.nextId == 2 then
                            pass "update persists"

                        else
                            fail "update persists"
                                "Expected id=1, title=\"Test todo\", completed=False, nextId=2"

                    _ ->
                        fail "update persists"
                            ("Expected 1 todo but got " ++ String.fromInt (List.length db.todos))
            )


{-| A second get should still see the persisted data.
-}
testGetReadsPersistedData : BackendTask FatalError ()
testGetReadsPersistedData =
    Script.log "Test: get reads persisted data"
        |> BackendTask.andThen (\_ -> Pages.Db.get Pages.Db.default)
        |> BackendTask.andThen
            (\db ->
                case db.todos of
                    [ todo ] ->
                        if todo.title == "Test todo" then
                            pass "get reads persisted"

                        else
                            fail "get reads persisted"
                                ("Expected title=\"Test todo\" but got \"" ++ todo.title ++ "\"")

                    _ ->
                        fail "get reads persisted"
                            ("Expected 1 todo but got " ++ String.fromInt (List.length db.todos))
            )


{-| Multiple updates should be additive.
-}
testUpdateIsAdditive : BackendTask FatalError ()
testUpdateIsAdditive =
    Script.log "Test: update is additive"
        |> BackendTask.andThen
            (\_ ->
                Pages.Db.update
                    Pages.Db.default
                    (\db ->
                        { db
                            | todos = db.todos ++ [ { id = db.nextId, title = "Second todo", completed = True } ]
                            , nextId = db.nextId + 1
                        }
                    )
            )
        |> BackendTask.andThen (\_ -> Pages.Db.get Pages.Db.default)
        |> BackendTask.andThen
            (\db ->
                if List.length db.todos == 2 then
                    pass "update additive"

                else
                    fail "update additive"
                        ("Expected 2 todos but got " ++ String.fromInt (List.length db.todos))
            )


{-| Transaction should return the value from the user function.
-}
testTransactionReturnsValue : BackendTask FatalError ()
testTransactionReturnsValue =
    Script.log "Test: transaction returns value"
        |> BackendTask.andThen
            (\_ ->
                Pages.Db.transaction
                    Pages.Db.default
                    (\db ->
                        let
                            count =
                                List.length db.todos
                        in
                        BackendTask.succeed
                            ( { db
                                | todos = db.todos ++ [ { id = db.nextId, title = "Third", completed = False } ]
                                , nextId = db.nextId + 1
                              }
                            , "count=" ++ String.fromInt count
                            )
                    )
            )
        |> BackendTask.andThen
            (\result ->
                if result == "count=2" then
                    Pages.Db.get Pages.Db.default
                        |> BackendTask.andThen
                            (\db ->
                                if List.length db.todos == 3 then
                                    pass "transaction returns value"

                                else
                                    fail "transaction returns value"
                                        ("Expected 3 todos but got " ++ String.fromInt (List.length db.todos))
                            )

                else
                    fail "transaction returns value"
                        ("Expected result=\"count=2\" but got \"" ++ result ++ "\"")
            )



-- Helpers


pass : String -> BackendTask FatalError ()
pass label =
    Script.log ("  PASS: " ++ label)


fail : String -> String -> BackendTask FatalError ()
fail label message =
    BackendTask.fail
        (FatalError.build
            { title = "FAIL: " ++ label
            , body = message
            }
        )


cleanup : BackendTask FatalError ()
cleanup =
    Script.exec "rm" [ "-f", "db.bin", "db.bin.lock", "db.lock" ]
