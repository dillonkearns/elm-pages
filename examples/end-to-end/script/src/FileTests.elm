module FileTests exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.File as File
import BackendTaskTest exposing (describe, test, testScript)
import Expect
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)


{-| All test artifacts go in this directory so they don't interfere with glob
pattern tests in the Cypress suite (which match \*.txt at the project root).
-}
testDir : String
testDir =
    ".file-test-artifacts"


run : Script
run =
    Script.makeDirectory { recursive = True } testDir
        |> BackendTask.andThen (\_ -> runTests)
        |> BackendTask.finally
            (Script.removeDirectory { recursive = True } testDir)
        |> Script.withoutCliOptions


runTests : BackendTask FatalError ()
runTests =
    [ describe "BackendTask.File.optional"
        [ test "existing file returns Just" <|
            \() ->
                File.rawFile "elm.json"
                    |> File.optional
                    |> BackendTask.map
                        (\result ->
                            case result of
                                Just content ->
                                    if String.length content > 0 then
                                        Expect.pass

                                    else
                                        Expect.fail "Expected non-empty content"

                                Nothing ->
                                    Expect.fail "Expected Just, got Nothing"
                        )
        , test "missing file returns Nothing" <|
            \() ->
                File.rawFile "does-not-exist.xyz"
                    |> File.optional
                    |> BackendTask.map (Expect.equal Nothing)
        ]
    , describe "BackendTask.finally"
        [ test "preserves success value" <|
            \() ->
                BackendTask.succeed 42
                    |> BackendTask.finally (Script.log "cleanup ran")
                    |> BackendTask.map (Expect.equal 42)
        , test "propagates cleanup error" <|
            \() ->
                BackendTask.succeed 42
                    |> BackendTask.finally
                        (BackendTask.fail (FatalError.build { title = "cleanup error", body = "should surface" }))
                    |> BackendTask.toResult
                    |> BackendTask.map
                        (\result ->
                            case result of
                                Ok value ->
                                    Expect.fail ("Expected cleanup error, got success: " ++ String.fromInt value)

                                Err _ ->
                                    Expect.pass
                        )
        ]
    , describe "BackendTask.File.exists"
        [ test "returns True for existing file" <|
            \() ->
                File.exists "elm.json"
                    |> BackendTask.map (Expect.equal True)
        , test "returns False for missing file" <|
            \() ->
                File.exists "does-not-exist.xyz"
                    |> BackendTask.map (Expect.equal False)
        ]
    , describe "Script.removeFile"
        [ test "removes a file" <|
            \() ->
                let
                    filePath =
                        testDir ++ "/delete-target.txt"
                in
                Script.writeFile { path = filePath, body = "delete me" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen
                        (\() ->
                            Script.removeFile filePath
                                |> BackendTask.andThen (\_ -> File.exists filePath)
                        )
                    |> BackendTask.map (Expect.equal False)
        , test "on missing file succeeds" <|
            \() ->
                Script.removeFile (testDir ++ "/nonexistent.txt")
                    |> BackendTask.map (\_ -> Expect.pass)
        ]
    , describe "Script.makeDirectory"
        [ test "recursive creates nested dirs" <|
            \() ->
                let
                    dirPath =
                        testDir ++ "/make-dir/nested/deep"
                in
                Script.makeDirectory { recursive = True } dirPath
                    |> BackendTask.andThen (\_ -> File.exists dirPath)
                    |> BackendTask.map (Expect.equal True)
        , test "non-recursive creates single dir" <|
            \() ->
                let
                    dirPath =
                        testDir ++ "/make-dir-single"
                in
                Script.removeDirectory { recursive = False } dirPath
                    |> BackendTask.andThen (\() -> Script.makeDirectory { recursive = False } dirPath)
                    |> BackendTask.map (\_ -> Expect.pass)
        ]
    , describe "Script.removeDirectory"
        [ test "recursive removes dir with contents" <|
            \() ->
                let
                    dirPath =
                        testDir ++ "/remove-dir"
                in
                Script.makeDirectory { recursive = True } dirPath
                    |> BackendTask.andThen
                        (\_ ->
                            Script.writeFile { path = dirPath ++ "/file.txt", body = "content" }
                                |> BackendTask.allowFatal
                        )
                    |> BackendTask.andThen (\() -> Script.removeDirectory { recursive = True } dirPath)
                    |> BackendTask.andThen (\() -> File.exists dirPath)
                    |> BackendTask.map (Expect.equal False)
        , test "on missing dir succeeds" <|
            \() ->
                Script.removeDirectory { recursive = True } (testDir ++ "/nonexistent-dir")
                    |> BackendTask.map (\() -> Expect.pass)
        , test "non-recursive removes empty dir" <|
            \() ->
                let
                    dirPath =
                        testDir ++ "/remove-empty-dir"
                in
                Script.makeDirectory { recursive = False } dirPath
                    |> BackendTask.andThen (\_ -> Script.removeDirectory { recursive = False } dirPath)
                    |> BackendTask.andThen (\() -> File.exists dirPath)
                    |> BackendTask.map (Expect.equal False)
        ]
    , describe "Script.copyFile"
        [ test "copies file contents" <|
            \() ->
                let
                    src =
                        testDir ++ "/copy-source.txt"

                    dest =
                        testDir ++ "/copy-dest.txt"
                in
                Script.writeFile { path = src, body = "copy me" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen (\() -> Script.copyFile { from = src, to = dest })
                    |> BackendTask.andThen (\_ -> File.rawFile dest |> BackendTask.allowFatal)
                    |> BackendTask.map (Expect.equal "copy me")
        , test "auto-creates parent dirs" <|
            \() ->
                let
                    src =
                        testDir ++ "/copy-source2.txt"

                    dest =
                        testDir ++ "/copy-nested/deep/dest.txt"
                in
                Script.writeFile { path = src, body = "nested copy" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen (\() -> Script.copyFile { from = src, to = dest })
                    |> BackendTask.map (\_ -> Expect.pass)
        ]
    , describe "Script.move"
        [ test "moves file and source is gone" <|
            \() ->
                let
                    src =
                        testDir ++ "/move-source.txt"

                    dest =
                        testDir ++ "/move-dest.txt"
                in
                Script.writeFile { path = src, body = "move me" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen (\() -> Script.move { from = src, to = dest })
                    |> BackendTask.andThen
                        (\_ ->
                            BackendTask.map2 Tuple.pair
                                (File.rawFile dest |> BackendTask.allowFatal)
                                (File.exists src)
                        )
                    |> BackendTask.map
                        (\( content, sourceExists ) ->
                            Expect.all
                                [ \_ -> Expect.equal "move me" content
                                , \_ -> Expect.equal False sourceExists
                                ]
                                ()
                        )
        , test "auto-creates parent dirs" <|
            \() ->
                let
                    src =
                        testDir ++ "/move-source2.txt"

                    dest =
                        testDir ++ "/move-nested/deep/dest.txt"
                in
                Script.writeFile { path = src, body = "nested move" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen (\() -> Script.move { from = src, to = dest })
                    |> BackendTask.map (\_ -> Expect.pass)
        ]
    , describe "Script.makeTempDirectory"
        [ test "creates dir that exists with prefix" <|
            \() ->
                Script.makeTempDirectory "test-prefix-"
                    |> BackendTask.andThen
                        (\tmpDir ->
                            File.exists tmpDir
                                |> BackendTask.map (\exists -> ( tmpDir, exists ))
                        )
                    |> BackendTask.map
                        (\( tmpDir, exists ) ->
                            Expect.all
                                [ \_ -> Expect.equal True exists
                                , \_ ->
                                    if String.contains "test-prefix-" tmpDir then
                                        Expect.pass

                                    else
                                        Expect.fail ("Expected path to contain prefix, got: " ++ tmpDir)
                                ]
                                ()
                        )
        ]
    , describe "Integration: makeTempDirectory + finally"
        [ test "cleans up temp dir after success" <|
            \() ->
                Script.makeTempDirectory "integration-test-"
                    |> BackendTask.andThen
                        (\tmpDir ->
                            Script.writeFile { path = tmpDir ++ "/test.txt", body = "temp content" }
                                |> BackendTask.allowFatal
                                |> BackendTask.andThen (\() -> BackendTask.succeed tmpDir)
                                |> BackendTask.finally
                                    (Script.removeDirectory { recursive = True } tmpDir)
                        )
                    |> BackendTask.andThen (\tmpDir -> File.exists tmpDir)
                    |> BackendTask.map (Expect.equal False)
        , test "cleans up temp dir after failure" <|
            \() ->
                Script.makeTempDirectory "integration-fail-"
                    |> BackendTask.andThen
                        (\tmpDir ->
                            Script.writeFile { path = tmpDir ++ "/test.txt", body = "temp content" }
                                |> BackendTask.allowFatal
                                |> BackendTask.andThen (\() -> BackendTask.fail (FatalError.build { title = "intentional", body = "error" }))
                                |> BackendTask.finally
                                    (Script.removeDirectory { recursive = True } tmpDir)
                                |> BackendTask.toResult
                                |> BackendTask.andThen (\_ -> File.exists tmpDir)
                        )
                    |> BackendTask.map (Expect.equal False)
        ]
    ]
        |> BackendTaskTest.describe "File"
        |> BackendTaskTest.run
