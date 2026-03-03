module TestMigration exposing (run)

{-| E2E migration test with real Elm compilation.

Run with: cd examples/end-to-end && node ../../generator/src/cli.js run TestMigration

Requires lamdera on PATH (for Wire3 codec generation).

Follows the lamdera-db script/Test.elm pattern:

  - Orchestrates test phases by shelling out to subprocesses
  - Uses fixture files for V2 schema and migration
  - Saves/restores project state via a temp backup directory
  - Verifies migration via subprocess execution and state checks

-}

import BackendTask exposing (BackendTask)
import BackendTask.Stream as Stream
import FatalError exposing (FatalError)
import FilePath exposing (FilePath)
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Script.log "=== TestMigration: E2E migration test ==="
            |> BackendTask.andThen (\_ -> saveState)
            |> BackendTask.andThen
                (\backupDir ->
                    cleanState
                        |> BackendTask.andThen (\_ -> runPhases)
                        |> BackendTask.finally (restoreState backupDir)
                )
            |> BackendTask.andThen (\_ -> Script.log "\n=== TestMigration: ALL PHASES PASSED ===")
        )



-- Phase runners


runPhases : BackendTask FatalError ()
runPhases =
    phase1SeedV1
        |> BackendTask.andThen (\_ -> phase2CreateMigration)
        |> BackendTask.andThen (\_ -> phase3ImplementStub)
        |> BackendTask.andThen (\_ -> phase4RunWithAutoApply)
        |> BackendTask.andThen (\_ -> phase5VerifyState)



-- Phase 1: Seed V1 data


phase1SeedV1 : BackendTask FatalError ()
phase1SeedV1 =
    Script.log "\n--- Phase 1: Seed V1 data ---"
        |> BackendTask.andThen (\_ -> cliRun "SeedDb")
        |> BackendTask.andThen (\_ -> assertDbBinVersion 1 "after seeding")
        |> BackendTask.andThen (\_ -> Script.log "  Seeded db.bin with 3 todos at V1.")



-- Phase 2: Create migration snapshot (while Db.elm still has V1 schema)


phase2CreateMigration : BackendTask FatalError ()
phase2CreateMigration =
    Script.log "\n--- Phase 2: Create migration (snapshot V1) ---"
        |> BackendTask.andThen (\_ -> cliDbMigrate)
        |> BackendTask.andThen (\_ -> Script.log "  Migration snapshot created.")



-- Phase 3: Change schema to V2 and implement migration stub


phase3ImplementStub : BackendTask FatalError ()
phase3ImplementStub =
    Script.log "\n--- Phase 3: Update schema to V2 and implement migration ---"
        |> BackendTask.andThen (\_ -> cp "test/fixtures/migration/DbV2.elm" "script/src/Db.elm")
        |> BackendTask.andThen (\_ -> Script.log "  Copied V2 Db.elm.")
        |> BackendTask.andThen (\_ -> cp "test/fixtures/migration/MigrateV2.elm" "db/Db/Migrate/V2.elm")
        |> BackendTask.andThen (\_ -> Script.log "  Copied implemented migration.")



-- Phase 4: Run VerifyDb (triggers auto-apply migration, then reads db)


phase4RunWithAutoApply : BackendTask FatalError ()
phase4RunWithAutoApply =
    Script.log "\n--- Phase 4: Run VerifyDb (triggers auto-apply) ---"
        |> BackendTask.andThen (\_ -> cp "test/fixtures/migration/VerifyDb.elm" "script/src/VerifyDb.elm")
        |> BackendTask.andThen (\_ -> cliRun "VerifyDb")
        |> BackendTask.andThen (\_ -> Script.log "  VerifyDb completed successfully.")



-- Phase 5: Verify db.bin state after migration


phase5VerifyState : BackendTask FatalError ()
phase5VerifyState =
    Script.log "\n--- Phase 5: Verify db.bin state ---"
        |> BackendTask.andThen (\_ -> assertDbBinVersion 2 "after migration")
        |> BackendTask.andThen
            (\_ ->
                Script.command "node"
                    [ "-e"
                    , String.join "\n"
                        [ "const fs = require('fs');"
                        , "const {parseDbBinHeader} = require('../../generator/src/db-bin-format.js');"
                        , "const buf = fs.readFileSync('db.bin');"
                        , "const p = parseDbBinHeader(buf);"
                        , "console.log(p.wire3Data.length);"
                        ]
                    ]
            )
        |> BackendTask.andThen
            (\dataLength ->
                let
                    len =
                        String.trim dataLength |> String.toInt |> Maybe.withDefault 0
                in
                if len > 0 then
                    Script.log ("  PASS: db.bin has " ++ String.fromInt len ++ " bytes of Wire3 data")

                else
                    BackendTask.fail
                        (FatalError.build
                            { title = "FAIL: db.bin data check"
                            , body = "Expected Wire3 data length > 0 but got " ++ String.trim dataLength
                            }
                        )
            )



-- State management: save and restore


saveState : BackendTask FatalError String
saveState =
    Script.log "Saving state..."
        |> BackendTask.andThen
            (\_ ->
                Script.command "mktemp" [ "-d" ]
                    |> BackendTask.map String.trim
            )
        |> BackendTask.andThen
            (\backupDir ->
                cp "script/src/Db.elm" (backupDir ++ "/Db.elm")
                    |> BackendTask.andThen (\_ -> cpIfExists "db.bin" (backupDir ++ "/db.bin"))
                    |> BackendTask.andThen (\_ -> cpIfExists "db.bin.lock" (backupDir ++ "/db.bin.lock"))
                    |> BackendTask.andThen (\_ -> cpDirIfExists "db" (backupDir ++ "/db"))
                    |> BackendTask.map (\_ -> backupDir)
            )


cleanState : BackendTask FatalError ()
cleanState =
    Script.log "Cleaning state..."
        |> BackendTask.andThen (\_ -> Script.exec "rm" [ "-f", "db.bin", "db.bin.lock", "db.lock" ])
        |> BackendTask.andThen (\_ -> Script.exec "rm" [ "-rf", "db/schema-history" ])


restoreState : String -> BackendTask FatalError ()
restoreState backupDir =
    Script.log "\nRestoring state..."
        -- Restore Db.elm (always exists in backup)
        |> BackendTask.andThen (\_ -> cp (backupDir ++ "/Db.elm") "script/src/Db.elm")
        -- Clean test artifacts
        |> BackendTask.andThen (\_ -> Script.exec "rm" [ "-f", "db.bin", "db.bin.lock", "db.lock" ])
        |> BackendTask.andThen (\_ -> Script.exec "rm" [ "-rf", "db" ])
        -- Restore optional files
        |> BackendTask.andThen (\_ -> cpIfExists (backupDir ++ "/db.bin") "db.bin")
        |> BackendTask.andThen (\_ -> cpIfExists (backupDir ++ "/db.bin.lock") "db.bin.lock")
        |> BackendTask.andThen (\_ -> cpDirIfExists (backupDir ++ "/db") "db")
        -- Clean up VerifyDb.elm if left behind
        |> BackendTask.andThen (\_ -> Script.exec "rm" [ "-f", "script/src/VerifyDb.elm" ])
        -- Remove backup directory
        |> BackendTask.andThen (\_ -> Script.exec "rm" [ "-rf", backupDir ])



-- CLI helpers


cliRun : String -> BackendTask FatalError ()
cliRun scriptName =
    Script.exec "node" [ "../../generator/src/cli.js", "run", scriptName ]


cliDbMigrate : BackendTask FatalError ()
cliDbMigrate =
    Script.exec "node" [ "../../generator/src/cli.js", "db", "migrate" ]



-- Shell helpers


cp : String -> String -> BackendTask FatalError ()
cp from to =
    Script.exec "cp" [ from, to ]


cpIfExists : String -> String -> BackendTask FatalError ()
cpIfExists from to =
    Script.exec "sh" [ "-c", "test -f " ++ from ++ " && cp " ++ from ++ " " ++ to ++ " || true" ]


cpDirIfExists : String -> String -> BackendTask FatalError ()
cpDirIfExists from to =
    Script.exec "sh" [ "-c", "test -d " ++ from ++ " && cp -r " ++ from ++ " " ++ to ++ " || true" ]



-- Assertion helpers


assertDbBinVersion : Int -> String -> BackendTask FatalError ()
assertDbBinVersion expectedVersion label =
    Script.command "node"
        [ "-e"
        , String.join "\n"
            [ "const fs = require('fs');"
            , "const {parseDbBinHeader} = require('../../generator/src/db-bin-format.js');"
            , "const buf = fs.readFileSync('db.bin');"
            , "const p = parseDbBinHeader(buf);"
            , "console.log(p.schemaVersion);"
            ]
        ]
        |> BackendTask.andThen
            (\output ->
                let
                    actualVersion =
                        String.trim output |> String.toInt |> Maybe.withDefault -1
                in
                if actualVersion == expectedVersion then
                    Script.log ("  PASS: db.bin version is " ++ String.fromInt expectedVersion ++ " " ++ label)

                else
                    BackendTask.fail
                        (FatalError.build
                            { title = "FAIL: db.bin version check " ++ label
                            , body =
                                "Expected version "
                                    ++ String.fromInt expectedVersion
                                    ++ " but got "
                                    ++ String.trim output
                            }
                        )
            )
