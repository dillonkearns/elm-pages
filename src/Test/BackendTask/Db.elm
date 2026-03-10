module Test.BackendTask.Db exposing
    ( withDb, withDbSetTo
    , expectDb
    )

{-| Seed and assert on virtual database state in BackendTask tests.


## Test Setup

@docs withDb, withDbSetTo


## Terminal Assertion

@docs expectDb

-}

import Bytes exposing (Bytes)
import Expect exposing (Expectation)
import Test.BackendTask.Internal as Internal exposing (BackendTaskTest, TestSetup)


{-| Seed the virtual DB with the default seed value from the generated `testConfig`.

    import Pages.Db
    import Test.BackendTask as BackendTaskTest
    import Test.BackendTask.Db as BackendTaskDb

    BackendTaskTest.init
        |> BackendTaskDb.withDb Pages.Db.testConfig

-}
withDb :
    { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes, seed : db }
    -> TestSetup
    -> TestSetup
withDb config =
    Internal.withDb config


{-| Seed the virtual DB with a specific initial value.

    import Pages.Db
    import Test.BackendTask as BackendTaskTest
    import Test.BackendTask.Db as BackendTaskDb

    BackendTaskTest.init
        |> BackendTaskDb.withDbSetTo { counter = 5 } Pages.Db.testConfig

-}
withDbSetTo :
    db
    -> { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes }
    -> TestSetup
    -> TestSetup
withDbSetTo initialValue config =
    Internal.withDbSetTo initialValue config


{-| Assert on the virtual DB state after the script completes. This is a terminal
assertion that also checks the script completed successfully.

    import Expect
    import Pages.Db
    import Test.BackendTask.Db as BackendTaskDb

    myTask
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskDb.withDb Pages.Db.testConfig
            )
        |> BackendTaskDb.expectDb Pages.Db.testConfig
            (\db -> Expect.equal 1 db.counter)

-}
expectDb :
    { a | decode : Bytes -> Maybe db }
    -> (db -> Expectation)
    -> BackendTaskTest b
    -> Expectation
expectDb config assertion =
    Internal.expectDb config assertion
