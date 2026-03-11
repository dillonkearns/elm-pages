module FileTests exposing (run)

import BackendTask exposing (BackendTask)
import BackendTask.Env
import BackendTask.File as File
import BackendTaskTest exposing (describe, test, testScript)
import Expect
import FatalError exposing (FatalError)
import FilePath exposing (FilePath)
import FilePath.Internal
import Pages.Script as Script exposing (Script)


{-| All test artifacts go in this directory so they don't interfere with glob
pattern tests in the Cypress suite (which match \*.txt at the project root).
-}
testDir : String
testDir =
    ".file-test-artifacts"


testPath : String -> String
testPath relativePath =
    testDir ++ "/" ++ relativePath


run : Script
run =
    Script.makeDirectory { recursive = True } testDir
        |> BackendTask.andThen (\_ -> runTests)
        |> BackendTask.finally
            (Script.removeDirectory { recursive = True } testDir)
        |> Script.withoutCliOptions


runTests : BackendTask FatalError ()
runTests =
    [ describe "FilePath.fromString normalization"
        [ test "empty path normalizes to dot" <|
            \() ->
                FilePath.fromString ""
                    |> FilePath.toString
                    |> Expect.equal "."
                    |> BackendTask.succeed
        , test "collapses duplicate separators and dot segments" <|
            \() ->
                FilePath.fromString "foo//bar/./baz/"
                    |> FilePath.toString
                    |> Expect.equal "foo/bar/baz"
                    |> BackendTask.succeed
        , test "resolves parent segments when possible" <|
            \() ->
                FilePath.fromString "foo/bar/../baz"
                    |> FilePath.toString
                    |> Expect.equal "foo/baz"
                    |> BackendTask.succeed
        , test "keeps unresolved parents for relative paths" <|
            \() ->
                FilePath.fromString "../../foo"
                    |> FilePath.toString
                    |> Expect.equal "../../foo"
                    |> BackendTask.succeed
        , test "does not go above POSIX root" <|
            \() ->
                FilePath.fromString "/foo/../../bar"
                    |> FilePath.toString
                    |> Expect.equal "/bar"
                    |> BackendTask.succeed
        , test "normalizes Windows absolute paths" <|
            \() ->
                FilePath.fromString "C:\\foo\\..\\bar\\."
                    |> FilePath.toString
                    |> Expect.equal "C:/bar"
                    |> BackendTask.succeed
        , test "preserves Windows drive-relative semantics" <|
            \() ->
                FilePath.fromString "C:foo\\..\\bar"
                    |> FilePath.toString
                    |> Expect.equal "C:bar"
                    |> BackendTask.succeed
        , test "normalizes UNC style paths" <|
            \() ->
                FilePath.fromString "\\\\server\\share\\folder\\..\\file.txt"
                    |> FilePath.toString
                    |> Expect.equal "//server/share/file.txt"
                    |> BackendTask.succeed
        , test "absolute detection handles POSIX, UNC, and Windows" <|
            \() ->
                Expect.all
                    [ \_ -> Expect.equal True (FilePath.fromString "/foo" |> FilePath.toString |> FilePath.Internal.isAbsolute)
                    , \_ -> Expect.equal True (FilePath.fromString "//server/share" |> FilePath.toString |> FilePath.Internal.isAbsolute)
                    , \_ -> Expect.equal True (FilePath.fromString "C:/foo" |> FilePath.toString |> FilePath.Internal.isAbsolute)
                    , \_ -> Expect.equal False (FilePath.fromString "C:foo" |> FilePath.toString |> FilePath.Internal.isAbsolute)
                    , \_ -> Expect.equal False (FilePath.fromString "../foo" |> FilePath.toString |> FilePath.Internal.isAbsolute)
                    ]
                    ()
                    |> BackendTask.succeed
        ]
    , describe "FilePath.append normalization"
        [ test "append resolves parent segments" <|
            \() ->
                FilePath.append
                    (FilePath.fromString "a/b")
                    (FilePath.fromString "../c")
                    |> FilePath.toString
                    |> Expect.equal "a/c"
                    |> BackendTask.succeed
        ]
    , describe "BackendTask.File.optional"
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
                        testPath "delete-target.txt"
                in
                Script.writeFile { path = filePath, body = "delete me" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen
                        (\_ ->
                            Script.removeFile filePath
                                |> BackendTask.andThen (\() -> File.exists filePath)
                        )
                    |> BackendTask.map (Expect.equal False)
        , test "on missing file succeeds" <|
            \() ->
                Script.removeFile (testPath "nonexistent.txt")
                    |> BackendTask.map (\() -> Expect.pass)
        ]
    , describe "Script.makeDirectory"
        [ test "recursive creates nested dirs" <|
            \() ->
                let
                    dirPath =
                        testPath "make-dir/nested/deep"
                in
                Script.makeDirectory { recursive = True } dirPath
                    |> BackendTask.andThen (\_ -> File.exists dirPath)
                    |> BackendTask.map (Expect.equal True)
        , test "non-recursive creates single dir" <|
            \() ->
                let
                    dirPath =
                        testPath "make-dir-single"
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
                        testPath "remove-dir"
                in
                Script.makeDirectory { recursive = True } dirPath
                    |> BackendTask.andThen
                        (\_ ->
                            Script.writeFile
                                { path = dirPath ++ "/file.txt"
                                , body = "content"
                                }
                                |> BackendTask.allowFatal
                        )
                    |> BackendTask.andThen (\_ -> Script.removeDirectory { recursive = True } dirPath)
                    |> BackendTask.andThen (\() -> File.exists dirPath)
                    |> BackendTask.map (Expect.equal False)
        , test "on missing dir succeeds" <|
            \() ->
                Script.removeDirectory { recursive = True } (testPath "nonexistent-dir")
                    |> BackendTask.map (\() -> Expect.pass)
        , test "non-recursive removes empty dir" <|
            \() ->
                let
                    dirPath =
                        testPath "remove-empty-dir"
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
                        testPath "copy-source.txt"

                    dest =
                        testPath "copy-dest.txt"
                in
                Script.writeFile { path = src, body = "copy me" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen (\_ -> Script.copyFile { from = src, to = dest })
                    |> BackendTask.andThen (\_ -> File.rawFile dest |> BackendTask.allowFatal)
                    |> BackendTask.map (Expect.equal "copy me")
        , test "auto-creates parent dirs" <|
            \() ->
                let
                    src =
                        testPath "copy-source2.txt"

                    dest =
                        testPath "copy-nested/deep/dest.txt"
                in
                Script.writeFile { path = src, body = "nested copy" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen (\_ -> Script.copyFile { from = src, to = dest })
                    |> BackendTask.map (\_ -> Expect.pass)
        ]
    , describe "Script.move"
        [ test "moves file and source is gone" <|
            \() ->
                let
                    src =
                        testPath "move-source.txt"

                    dest =
                        testPath "move-dest.txt"
                in
                Script.writeFile { path = src, body = "move me" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen (\_ -> Script.move { from = src, to = dest })
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
                        testPath "move-source2.txt"

                    dest =
                        testPath "move-nested/deep/dest.txt"
                in
                Script.writeFile { path = src, body = "nested move" }
                    |> BackendTask.allowFatal
                    |> BackendTask.andThen (\_ -> Script.move { from = src, to = dest })
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
                            Script.writeFile
                                { path = tmpDir ++ "/test.txt"
                                , body = "temp content"
                                }
                                |> BackendTask.allowFatal
                                |> BackendTask.andThen (\_ -> BackendTask.succeed tmpDir)
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
                            Script.writeFile
                                { path = tmpDir ++ "/test.txt"
                                , body = "temp content"
                                }
                                |> BackendTask.allowFatal
                                |> BackendTask.andThen (\_ -> BackendTask.fail (FatalError.build { title = "intentional", body = "error" }))
                                |> BackendTask.finally
                                    (Script.removeDirectory { recursive = True } tmpDir)
                                |> BackendTask.toResult
                                |> BackendTask.andThen (\_ -> File.exists tmpDir)
                        )
                    |> BackendTask.map (Expect.equal False)
        ]
    , describe "FilePath.resolve"
        [ test "idempotent - resolving an already-resolved path returns the same path" <|
            \() ->
                FilePath.fromString "src/Main.elm"
                    |> FilePath.resolve
                    |> BackendTask.andThen FilePath.resolve
                    |> BackendTask.andThen
                        (\resolvedTwice ->
                            FilePath.fromString "src/Main.elm"
                                |> FilePath.resolve
                                |> BackendTask.map
                                    (\resolvedOnce ->
                                        Expect.equal
                                            (FilePath.toString resolvedOnce)
                                            (FilePath.toString resolvedTwice)
                                    )
                        )
        , test "parent traversal - foo/../bar resolves same as bar" <|
            \() ->
                BackendTask.map2
                    (\withParent direct ->
                        Expect.equal
                            (FilePath.toString direct)
                            (FilePath.toString withParent)
                    )
                    (FilePath.fromString "foo/../bar"
                        |> FilePath.resolve
                    )
                    (FilePath.fromString "bar"
                        |> FilePath.resolve
                    )
        , test "dot and empty resolve to the same path" <|
            \() ->
                BackendTask.map2
                    (\dotResolved emptyResolved ->
                        Expect.equal
                            (FilePath.toString emptyResolved)
                            (FilePath.toString dotResolved)
                    )
                    (FilePath.fromString "."
                        |> FilePath.resolve
                    )
                    (FilePath.fromString ""
                        |> FilePath.resolve
                    )
        ]
    , describe "BackendTask.withEnv + Env.get"
        [ test "withEnv makes variable visible to Env.get" <|
            \() ->
                BackendTask.Env.get "TEST_WITH_ENV_VAR"
                    |> BackendTask.withEnv "TEST_WITH_ENV_VAR" "injected-value"
                    |> BackendTask.map
                        (Expect.equal (Just "injected-value"))
        , test "withEnv overrides existing env var for Env.get" <|
            \() ->
                -- PATH always exists, so withEnv should override it
                BackendTask.Env.get "PATH"
                    |> BackendTask.withEnv "PATH" "overridden"
                    |> BackendTask.map
                        (Expect.equal (Just "overridden"))
        ]
    ]
        |> BackendTaskTest.describe "File"
        |> BackendTaskTest.run
