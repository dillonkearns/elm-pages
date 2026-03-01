module DbTests exposing (run)

{-| Integration tests for the Pages.Db built-in database.

Run with: cd examples/end-to-end/script && npx elm-pages run DbTests

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
        |> BackendTask.andThen (\_ -> Pages.Db.get)
        |> BackendTask.andThen
            (\db ->
                if db.counter == 0 && db.name == "" then
                    pass "get returns init"

                else
                    fail "get returns init"
                        ("Expected { counter = 0, name = \"\" } but got { counter = "
                            ++ String.fromInt db.counter
                            ++ ", name = \""
                            ++ db.name
                            ++ "\" }"
                        )
            )


{-| After update, the new data should be persisted.
-}
testUpdatePersistsData : BackendTask FatalError ()
testUpdatePersistsData =
    Script.log "Test: update persists data"
        |> BackendTask.andThen
            (\_ ->
                Pages.Db.update (\db -> { db | counter = 42, name = "test" })
            )
        |> BackendTask.andThen (\_ -> Pages.Db.get)
        |> BackendTask.andThen
            (\db ->
                if db.counter == 42 && db.name == "test" then
                    pass "update persists"

                else
                    fail "update persists"
                        ("Expected counter=42, name=\"test\" but got counter="
                            ++ String.fromInt db.counter
                            ++ ", name=\""
                            ++ db.name
                            ++ "\""
                        )
            )


{-| A second get should still see the persisted data.
-}
testGetReadsPersistedData : BackendTask FatalError ()
testGetReadsPersistedData =
    Script.log "Test: get reads persisted data"
        |> BackendTask.andThen (\_ -> Pages.Db.get)
        |> BackendTask.andThen
            (\db ->
                if db.counter == 42 && db.name == "test" then
                    pass "get reads persisted"

                else
                    fail "get reads persisted"
                        ("Expected counter=42 but got counter=" ++ String.fromInt db.counter)
            )


{-| Multiple updates should be additive.
-}
testUpdateIsAdditive : BackendTask FatalError ()
testUpdateIsAdditive =
    Script.log "Test: update is additive"
        |> BackendTask.andThen
            (\_ ->
                Pages.Db.update (\db -> { db | counter = db.counter + 1 })
            )
        |> BackendTask.andThen (\_ -> Pages.Db.get)
        |> BackendTask.andThen
            (\db ->
                if db.counter == 43 then
                    pass "update additive"

                else
                    fail "update additive"
                        ("Expected counter=43 but got counter=" ++ String.fromInt db.counter)
            )


{-| Transaction should return the value from the user function.
-}
testTransactionReturnsValue : BackendTask FatalError ()
testTransactionReturnsValue =
    Script.log "Test: transaction returns value"
        |> BackendTask.andThen
            (\_ ->
                Pages.Db.transaction
                    (\db ->
                        let
                            oldCounter =
                                db.counter
                        in
                        BackendTask.succeed
                            ( { db | counter = db.counter + 10 }
                            , "old=" ++ String.fromInt oldCounter
                            )
                    )
            )
        |> BackendTask.andThen
            (\result ->
                if result == "old=43" then
                    -- Also verify the db was updated
                    Pages.Db.get
                        |> BackendTask.andThen
                            (\db ->
                                if db.counter == 53 then
                                    pass "transaction returns value"

                                else
                                    fail "transaction returns value"
                                        ("Expected counter=53 but got counter=" ++ String.fromInt db.counter)
                            )

                else
                    fail "transaction returns value"
                        ("Expected result=\"old=43\" but got \"" ++ result ++ "\"")
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
    Script.exec "rm" [ "-f", "db.bin", "db.lock" ]
