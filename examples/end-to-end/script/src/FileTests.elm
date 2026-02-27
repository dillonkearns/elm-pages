module FileTests exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.File as File
import BackendTaskTest exposing (describe, test, testScript)
import Expect
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)


run : Script
run =
    testScript "File"
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
            , test "suppresses cleanup error" <|
                \() ->
                    BackendTask.succeed 42
                        |> BackendTask.finally
                            (BackendTask.fail (FatalError.build { title = "cleanup error", body = "should be suppressed" }))
                        |> BackendTask.map (Expect.equal 42)
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
        , describe "Script.deleteFile"
            [ test "removes a file" <|
                \() ->
                    Script.writeFile { path = "test-delete-target.txt", body = "delete me" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen
                            (\() ->
                                Script.deleteFile "test-delete-target.txt"
                                    |> BackendTask.andThen (\_ -> File.exists "test-delete-target.txt")
                            )
                        |> BackendTask.map (Expect.equal False)
            , test "on missing file succeeds" <|
                \() ->
                    Script.deleteFile "nonexistent-delete-target.txt"
                        |> BackendTask.map (\_ -> Expect.pass)
            ]
        , describe "Script.makeDirectory"
            [ test "recursive creates nested dirs" <|
                \() ->
                    Script.makeDirectory { recursive = True } "test-make-dir/nested/deep"
                        |> BackendTask.andThen (\_ -> File.exists "test-make-dir/nested/deep")
                        |> BackendTask.map (Expect.equal True)
            , test "non-recursive creates single dir" <|
                \() ->
                    Script.removeDirectory { recursive = False } "test-make-dir-single"
                        |> BackendTask.andThen (\() -> Script.makeDirectory { recursive = False } "test-make-dir-single")
                        |> BackendTask.map (\_ -> Expect.pass)
            ]
        , describe "Script.removeDirectory"
            [ test "recursive removes dir with contents" <|
                \() ->
                    Script.makeDirectory { recursive = True } "test-remove-dir"
                        |> BackendTask.andThen
                            (\_ ->
                                Script.writeFile { path = "test-remove-dir/file.txt", body = "content" }
                                    |> BackendTask.allowFatal
                            )
                        |> BackendTask.andThen (\() -> Script.removeDirectory { recursive = True } "test-remove-dir")
                        |> BackendTask.andThen (\() -> File.exists "test-remove-dir")
                        |> BackendTask.map (Expect.equal False)
            , test "on missing dir succeeds" <|
                \() ->
                    Script.removeDirectory { recursive = True } "nonexistent-remove-dir"
                        |> BackendTask.map (\() -> Expect.pass)
            , test "non-recursive removes empty dir" <|
                \() ->
                    Script.makeDirectory { recursive = False } "test-remove-empty-dir"
                        |> BackendTask.andThen (\_ -> Script.removeDirectory { recursive = False } "test-remove-empty-dir")
                        |> BackendTask.andThen (\() -> File.exists "test-remove-empty-dir")
                        |> BackendTask.map (Expect.equal False)
            ]
        , describe "Script.copyFile"
            [ test "copies file contents" <|
                \() ->
                    Script.writeFile { path = "test-copy-source.txt", body = "copy me" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.copyFile { from = "test-copy-source.txt", to = "test-copy-dest.txt" })
                        |> BackendTask.andThen (\_ -> File.rawFile "test-copy-dest.txt" |> BackendTask.allowFatal)
                        |> BackendTask.map (Expect.equal "copy me")
            , test "auto-creates parent dirs" <|
                \() ->
                    Script.writeFile { path = "test-copy-source2.txt", body = "nested copy" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.copyFile { from = "test-copy-source2.txt", to = "test-copy-nested/deep/dest.txt" })
                        |> BackendTask.map (\_ -> Expect.pass)
            ]
        , describe "Script.move"
            [ test "moves file and source is gone" <|
                \() ->
                    Script.writeFile { path = "test-move-source.txt", body = "move me" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.move { from = "test-move-source.txt", to = "test-move-dest.txt" })
                        |> BackendTask.andThen
                            (\_ ->
                                BackendTask.map2 Tuple.pair
                                    (File.rawFile "test-move-dest.txt" |> BackendTask.allowFatal)
                                    (File.exists "test-move-source.txt")
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
                    Script.writeFile { path = "test-move-source2.txt", body = "nested move" }
                        |> BackendTask.allowFatal
                        |> BackendTask.andThen (\() -> Script.move { from = "test-move-source2.txt", to = "test-move-nested/deep/dest.txt" })
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
