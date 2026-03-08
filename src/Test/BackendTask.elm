module Test.BackendTask exposing
    ( BackendTaskTest, HttpError(..), fromBackendTask, fromBackendTaskWith, fromBackendTaskWithDb, fromScript, fromScriptWith
    , TestSetup, defaultSetup, withFile, withBinaryFile, withDb, withStdin, withEnv, withTime, withRandomSeed, withWhich
    , simulateHttpGet, simulateHttpPost, simulateHttpError, simulateCustom, simulateCommand, simulateCustomStream, simulateStreamHttp
    , simulateQuestion, simulateReadKey
    , ensureHttpGet, ensureHttpPost, ensureCustom, ensureLogged, ensureFileWritten, ensureStdout, ensureStderr
    , ensureFile, ensureFileExists, ensureNoFile
    , SimulatedEffect, withSimulatedEffects, writeFileEffect, removeFileEffect
    , expectSuccess, expectSuccessWith, expectDb, expectFailure, expectFailureWith, expectTestError
    )

{-| Pure Elm testing for `BackendTask` pipelines — no side effects, no HTTP calls, no file I/O.

You build a test by creating a `BackendTaskTest` from your `BackendTask`, simulating each
external effect (HTTP requests, custom port calls), optionally asserting on tracked effects
(log messages, file writes), and finishing with a terminal assertion.

    import BackendTask
    import BackendTask.Http
    import Expect
    import FatalError exposing (FatalError)
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Pages.Script as Script
    import Test exposing (test)
    import Test.BackendTask as BackendTaskTest

    test "fetches stars and logs the count" <|
        \() ->
            BackendTask.Http.getJson
                "https://api.github.com/repos/dillonkearns/elm-pages"
                (Decode.field "stargazers_count" Decode.int)
                |> BackendTask.allowFatal
                |> BackendTask.andThen
                    (\stars -> Script.log (String.fromInt stars))
                |> BackendTaskTest.fromBackendTask
                |> BackendTaskTest.simulateHttpGet
                    "https://api.github.com/repos/dillonkearns/elm-pages"
                    (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
                |> BackendTaskTest.ensureLogged "86"
                |> BackendTaskTest.expectSuccess

Fire-and-forget effects like `Script.log` and `Script.writeFile` are resolved automatically —
you never need to simulate them. But you can still assert that they happened using
`ensureLogged` and `ensureFileWritten`.


## What gets auto-resolved vs. what you simulate

Most built-in operations resolve automatically against virtual state — you only need to
simulate things the framework can't predict (HTTP, shell commands, custom ports).

**Auto-resolved (no simulation needed):**

  - `Script.log`, `Script.writeFile`, `Script.removeFile`, `Script.copyFile`, `Script.move`
  - `BackendTask.File.rawFile`, `BackendTask.File.jsonFile`, `BackendTask.File.exists`
  - `BackendTask.Env.get`, `BackendTask.Env.expect`
  - `Stream.fromString`, `Stream.stdin`, `Stream.stdout`, `Stream.stderr`
  - `Stream.fileRead`, `Stream.fileWrite`
  - `Stream.gzip`, `Stream.unzip`

All of these read from or write to virtual state. Use `withFile` to seed files, `withEnv` to
seed environment variables, `ensureFile` to assert on files, and
`ensureLogged`/`ensureStdout`/`ensureStderr` to check output.

**Needs simulation:**

  - `BackendTask.Http.*` — use `simulateHttpGet`, `simulateHttpPost`, `simulateHttpError`
  - `BackendTask.Custom.run` — use `simulateCustom`
  - `Stream.command` / `Script.command` / `Script.exec` — use `simulateCommand`
  - `Stream.customRead` / `Stream.customWrite` / `Stream.customDuplex` — use `simulateCustomStream`
  - `Stream.http` / `Stream.httpWithInput` — use `simulateStreamHttp`

For stream pipelines that mix both (e.g. `fileRead |> command |> fileWrite`), the framework
handles the auto-resolvable parts around the opaque part — you only provide the opaque part's
output.

`BackendTask.inDir` is fully supported — file paths are resolved relative to the working
directory, so `inDir "subdir" (File.rawFile "config.json")` reads `subdir/config.json` from
the virtual filesystem.


## What this framework does NOT test

  - **Decoder correctness against real HTTP responses** — You provide simulated JSON, so the
    framework can't catch mismatches between your decoder and the actual API response shape.
    Consider supplementing with contract tests or golden-file tests for critical decoders.
  - **Actual file system behavior** — Permissions, symlinks, encoding issues, race conditions,
    and OS-specific path handling are not modeled. The virtual filesystem is a simple
    `Dict String String`.
  - **Real shell command behavior** — `simulateCommand` provides canned output. It doesn't
    validate that the command exists, that the arguments are correct, or what the command
    would actually produce.
  - **Timing and concurrency** — `BackendTask.map2` dispatches requests in parallel in
    production, and you can verify this with `ensureHttpGet`/`ensureHttpPost`, but actual
    timing, race conditions, and timeout behavior are not modeled.
  - **Network conditions** — Beyond `simulateHttpError` with `NetworkError`/`Timeout`, there
    is no simulation of slow responses, partial failures, or retries.


## Building

@docs BackendTaskTest, HttpError, fromBackendTask, fromBackendTaskWith, fromBackendTaskWithDb, fromScript, fromScriptWith


## Test Setup

Configure the initial state (seeded files, DB) before the test starts running.

@docs TestSetup, defaultSetup, withFile, withBinaryFile, withDb, withStdin, withEnv, withTime, withRandomSeed, withWhich


## Simulating Effects

@docs simulateHttpGet, simulateHttpPost, simulateHttpError, simulateCustom, simulateCommand, simulateCustomStream, simulateStreamHttp

@docs simulateQuestion, simulateReadKey


## Inline Assertions

These check conditions mid-pipeline without ending the test. They return the same
`BackendTaskTest` so you can keep chaining.

@docs ensureHttpGet, ensureHttpPost, ensureCustom, ensureLogged, ensureFileWritten, ensureStdout, ensureStderr


## Virtual Filesystem

Built-in filesystem operations (`Script.writeFile`, `Script.removeFile`, etc.) are tracked
in a virtual filesystem. Assert on the final state with these functions.

@docs ensureFile, ensureFileExists, ensureNoFile


## Simulated Effects

Declare virtual filesystem side effects for custom ports. When a custom port is resolved
via [`simulateCustom`](#simulateCustom), the registered handler's effects are applied to the
virtual filesystem automatically.

@docs SimulatedEffect, withSimulatedEffects, writeFileEffect, removeFileEffect


## Terminal Assertions

These end the pipeline and produce an `Expectation` for elm-test.

@docs expectSuccess, expectSuccessWith, expectDb, expectFailure, expectFailureWith, expectTestError

-}

import BackendTask exposing (BackendTask)
import Bytes exposing (Bytes)
import Bytes.Encode as BE
import Cli.Program as Program
import Dict exposing (Dict)
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.FatalError
import Pages.Internal.Script
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.StaticHttp.Request as Request
import Pages.StaticHttpRequest exposing (RawRequest(..), Status(..))
import RequestsAndPending
import Set
import Test.GlobMatch
import Test.Runner
import Time


{-| The state of a `BackendTask` under test. Create one with [`fromBackendTask`](#fromBackendTask),
simulate external effects, and finish with [`expectSuccess`](#expectSuccess) or [`expectFailure`](#expectFailure).

    BackendTask.succeed ()
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

-}
type BackendTaskTest a
    = Running (RunningState a)
    | Done (DoneState a)
    | TestError String


type alias VirtualFS =
    { files : Dict String String
    , binaryFiles : Dict String Bytes
    , stdin : Maybe String
    , env : Dict String String
    , time : Maybe Time.Posix
    , randomSeed : Maybe Int
    , whichCommands : Dict String String
    , tempDirCounter : Int
    }


emptyVirtualFS : VirtualFS
emptyVirtualFS =
    { files = Dict.empty
    , binaryFiles = Dict.empty
    , stdin = Nothing
    , env = Dict.empty
    , time = Nothing
    , randomSeed = Nothing
    , whichCommands = Dict.empty
    , tempDirCounter = 0
    }


type alias VirtualDB =
    { state : Maybe Bytes
    , dbConfig : Maybe DbConfig
    }


type alias DbConfig =
    { schemaVersion : Int
    , schemaHash : String
    }


emptyVirtualDB : VirtualDB
emptyVirtualDB =
    { state = Nothing
    , dbConfig = Nothing
    }


type TrackedEffect
    = LogEffect String
    | FileWriteEffect { path : String, body : String }
    | StdoutEffect String
    | StderrEffect String


{-| An effect on the virtual filesystem that a custom port declares via
[`withSimulatedEffects`](#withSimulatedEffects). Create values with
[`writeFileEffect`](#writeFileEffect) and [`removeFileEffect`](#removeFileEffect).
-}
type SimulatedEffect
    = SimWriteFile { path : String, body : String }
    | SimRemoveFile String


{-| The type of HTTP error to simulate with [`simulateHttpError`](#simulateHttpError).

    BackendTaskTest.simulateHttpError
        "GET"
        "https://api.example.com/data"
        BackendTaskTest.NetworkError

-}
type HttpError
    = NetworkError
    | Timeout


{-| Configuration for the initial state of a test. Create with [`defaultSetup`](#defaultSetup),
then configure with [`withFile`](#withFile) and [`withDb`](#withDb).

    BackendTaskTest.defaultSetup
        |> BackendTaskTest.withFile "config.json" """{"key":"value"}"""
        |> BackendTaskTest.withDb Pages.Db.testConfig { counter = 0 }

-}
type TestSetup
    = TestSetup
        { virtualFS : VirtualFS
        , virtualDB : VirtualDB
        }


{-| An empty test setup with no seeded files or DB state.
-}
defaultSetup : TestSetup
defaultSetup =
    TestSetup
        { virtualFS = emptyVirtualFS
        , virtualDB = emptyVirtualDB
        }


{-| Seed a file into the virtual filesystem before the test starts running.

    import BackendTask.Stream as Stream
    import Test.BackendTask as BackendTaskTest

    Stream.fileRead "config.json"
        |> Stream.read
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\{ body } -> Script.log body)
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withFile "config.json" """{"key":"value"}"""
            )
        |> BackendTaskTest.ensureLogged """{"key":"value"}"""
        |> BackendTaskTest.expectSuccess

-}
withFile : String -> String -> TestSetup -> TestSetup
withFile path content (TestSetup setup) =
    TestSetup { setup | virtualFS = insertFile path content setup.virtualFS }


{-| Seed a binary file into the virtual filesystem before the test starts running.
Use this for testing `BackendTask.File.binaryFile`.

    import BackendTask.File
    import Bytes.Encode
    import Test.BackendTask as BackendTaskTest

    let
        testBytes =
            Bytes.Encode.encode
                (Bytes.Encode.unsignedInt8 42)
    in
    BackendTask.File.binaryFile "data.bin"
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\bytes -> Script.log (String.fromInt (Bytes.width bytes)))
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withBinaryFile "data.bin" testBytes
            )
        |> BackendTaskTest.ensureLogged "1"
        |> BackendTaskTest.expectSuccess

-}
withBinaryFile : String -> Bytes -> TestSetup -> TestSetup
withBinaryFile path content (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | binaryFiles = Dict.insert path content vfs.binaryFiles } }


{-| Seed the virtual DB with a typed value before the test starts running.

    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    myDbScript
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withDb Pages.Db.testConfig { counter = 0 }
            )
        |> BackendTaskTest.expectDb Pages.Db.testConfig
            (\db -> Expect.equal 1 db.counter)

-}
withDb :
    { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes }
    -> db
    -> TestSetup
    -> TestSetup
withDb config initialValue (TestSetup setup) =
    let
        wire3Bytes =
            config.encode initialValue
    in
    TestSetup
        { setup
            | virtualDB =
                { state = Just wire3Bytes
                , dbConfig = Just { schemaVersion = config.schemaVersion, schemaHash = config.schemaHash }
                }
        }


{-| Seed stdin content for stream pipelines that read from `Stream.stdin`.

    import BackendTask.Stream as Stream
    import Test.BackendTask as BackendTaskTest

    Stream.stdin
        |> Stream.read
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\{ body } -> Script.log body)
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withStdin "hello from stdin"
            )
        |> BackendTaskTest.ensureLogged "hello from stdin"
        |> BackendTaskTest.expectSuccess

-}
withStdin : String -> TestSetup -> TestSetup
withStdin content (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | stdin = Just content } }


{-| Seed an environment variable for `BackendTask.Env.get` and `BackendTask.Env.expect`.

    import BackendTask.Env
    import Test.BackendTask as BackendTaskTest

    BackendTask.Env.expect "API_KEY"
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\key -> Script.log key)
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withEnv "API_KEY" "secret123"
            )
        |> BackendTaskTest.ensureLogged "secret123"
        |> BackendTaskTest.expectSuccess

-}
withEnv : String -> String -> TestSetup -> TestSetup
withEnv name value (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | env = Dict.insert name value vfs.env } }


{-| Set a fixed virtual time for `BackendTask.Time.now`. Without this, any use of
`BackendTask.Time.now` will produce a test error with a helpful message.

    import BackendTask.Time
    import Time
    import Test.BackendTask as BackendTaskTest

    BackendTask.Time.now
        |> BackendTask.andThen
            (\time -> Script.log (String.fromInt (Time.posixToMillis time)))
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withTime (Time.millisToPosix 1709827200000)
            )
        |> BackendTaskTest.ensureLogged "1709827200000"
        |> BackendTaskTest.expectSuccess

-}
withTime : Time.Posix -> TestSetup -> TestSetup
withTime time (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | time = Just time } }


{-| Set a fixed random seed for `BackendTask.Random.int32` and `BackendTask.Random.generate`.
Without this, any use of `BackendTask.Random` will produce a test error with a helpful message.

The seed value is returned directly by `BackendTask.Random.int32`. For `BackendTask.Random.generate`,
the seed is used with `Random.initialSeed` to run the generator deterministically.

    import BackendTask.Random
    import Test.BackendTask as BackendTaskTest

    BackendTask.Random.int32
        |> BackendTask.andThen (\seed -> Script.log (String.fromInt seed))
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withRandomSeed 42
            )
        |> BackendTaskTest.ensureLogged "42"
        |> BackendTaskTest.expectSuccess

-}
withRandomSeed : Int -> TestSetup -> TestSetup
withRandomSeed seed (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | randomSeed = Just seed } }


{-| Register a command as available for `Script.which` and `Script.expectWhich`.
The first argument is the command name, the second is its full path.

    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.expectWhich "node"
        |> BackendTask.andThen Script.log
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withWhich "node" "/usr/bin/node"
            )
        |> BackendTaskTest.ensureLogged "/usr/bin/node"
        |> BackendTaskTest.expectSuccess

Commands not registered with `withWhich` will return `Nothing` from `Script.which`.

-}
withWhich : String -> String -> TestSetup -> TestSetup
withWhich commandName path (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | whichCommands = Dict.insert commandName path vfs.whichCommands } }


{-| Start a test from a `BackendTask FatalError ()`. Internal effects like `Script.log`
and `Script.writeFile` are automatically resolved — you only need to simulate external
effects like HTTP requests and `BackendTask.Custom.run` calls.

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    -- Script.log is auto-resolved, no simulation needed
    Script.log "Hello!"
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

-}
fromBackendTask : BackendTask FatalError a -> BackendTaskTest a
fromBackendTask =
    fromBackendTaskWith defaultSetup


{-| Start a test with a configured [`TestSetup`](#TestSetup). Use this when you need
to seed initial files or DB state.

    import BackendTask.File
    import Test.BackendTask as BackendTaskTest

    BackendTask.File.rawFile "config.json"
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\content -> Script.log content)
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withFile "config.json" """{"key":"value"}"""
            )
        |> BackendTaskTest.ensureLogged """{"key":"value"}"""
        |> BackendTaskTest.expectSuccess

-}
fromBackendTaskWith : TestSetup -> BackendTask FatalError a -> BackendTaskTest a
fromBackendTaskWith (TestSetup setup) task =
    advanceWithAutoResolve
        { continuation = task
        , responseEntries = []
        , responseBytesEntries = Dict.empty
        , pendingRequests = []
        , trackedEffects = []
        , virtualFS = setup.virtualFS
        , virtualDB = setup.virtualDB
        , simulatedEffects = Nothing
        }


{-| Start a test from a `BackendTask` that uses `Pages.Db`. Pass the generated
`Pages.Db.testConfig` and an initial DB value. All DB operations (`get`, `update`,
`transaction`) will be auto-resolved against a virtual DB.

    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    myDbScript
        |> BackendTaskTest.fromBackendTaskWithDb Pages.Db.testConfig
            { counter = 0 }
        |> BackendTaskTest.expectDb Pages.Db.testConfig
            (\db -> Expect.equal 1 db.counter)

If a script uses `Pages.Db` but is created with [`fromBackendTask`](#fromBackendTask)
instead, you'll get a helpful error message.

This is a convenience for `fromBackendTaskWith (defaultSetup |> withDb config initialValue)`.

-}
fromBackendTaskWithDb :
    { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes }
    -> db
    -> BackendTask FatalError ()
    -> BackendTaskTest ()
fromBackendTaskWithDb config initialValue =
    fromBackendTaskWith (defaultSetup |> withDb config initialValue)


{-| Start a test from a [`Script`](Pages-Script#Script) value with simulated CLI arguments.
This lets you test the full script including CLI option parsing.

    import Cli.Option as Option
    import Cli.OptionsParser as OptionsParser
    import Cli.Program as Program
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.withCliOptions
        (Program.config
            |> Program.add
                (OptionsParser.build (\name -> { name = name })
                    |> OptionsParser.with
                        (Option.optionalKeywordArg "name"
                            |> Option.withDefault "world"
                        )
                )
        )
        (\{ name } -> Script.log ("Hello, " ++ name ++ "!"))
        |> BackendTaskTest.fromScript [ "--name", "Dillon" ]
        |> BackendTaskTest.ensureLogged "Hello, Dillon!"
        |> BackendTaskTest.expectSuccess

If the CLI arguments don't match the expected options, you get a `TestError`
with the CLI parser's error message.

-}
fromScript : List String -> Pages.Internal.Script.Script -> BackendTaskTest ()
fromScript =
    fromScriptWith defaultSetup


{-| Like [`fromScript`](#fromScript) but with a configured [`TestSetup`](#TestSetup).

    myScript
        |> BackendTaskTest.fromScriptWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withFile "config.json" "{}"
            )
            [ "--verbose" ]
        |> BackendTaskTest.expectSuccess

-}
fromScriptWith : TestSetup -> List String -> Pages.Internal.Script.Script -> BackendTaskTest ()
fromScriptWith setup cliArgs (Pages.Internal.Script.Script toConfig) =
    let
        programConfig : Program.Config (BackendTask FatalError ())
        programConfig =
            toConfig (\_ _ -> "")

        argv : List String
        argv =
            "node" :: "elm-pages-test" :: cliArgs
    in
    case Program.run programConfig argv "" Program.WithoutColor of
        Program.CustomMatch task ->
            fromBackendTaskWith setup task

        Program.SystemMessage _ message ->
            TestError ("fromScript: CLI argument parsing failed:\n\n" ++ message)


type alias RunningState a =
    { continuation : RawRequest FatalError a
    , responseEntries : List ( String, Encode.Value )
    , responseBytesEntries : Dict String Bytes
    , pendingRequests : List Request.Request
    , trackedEffects : List TrackedEffect
    , virtualFS : VirtualFS
    , virtualDB : VirtualDB
    , simulatedEffects : Maybe (String -> Encode.Value -> List SimulatedEffect)
    }


type alias DoneState a =
    { result : Result FatalError a
    , trackedEffects : List TrackedEffect
    , virtualFS : VirtualFS
    , virtualDB : VirtualDB
    }


advanceWithAutoResolve : RunningState a -> BackendTaskTest a
advanceWithAutoResolve state =
    advanceWithAutoResolveHelper 1000 state


advanceWithAutoResolveHelper : Int -> RunningState a -> BackendTaskTest a
advanceWithAutoResolveHelper fuel state =
    if fuel <= 0 then
        TestError "BackendTaskTest: Too many auto-resolve steps. Does your BackendTask have an infinite loop?"

    else
        let
            requestsAndPending : RequestsAndPending.RequestsAndPending
            requestsAndPending =
                { json = Encode.object state.responseEntries
                , rawBytes = state.responseBytesEntries
                }
        in
        case Pages.StaticHttpRequest.cacheRequestResolution state.continuation requestsAndPending of
            Complete result ->
                Done
                    { result = result
                    , trackedEffects = state.trackedEffects
                    , virtualFS = state.virtualFS
                    , virtualDB = state.virtualDB
                    }

            HasPermanentError err ->
                TestError (permanentErrorToString err)

            Incomplete pendingRequests continuation ->
                let
                    ( autoResolvable, external ) =
                        List.partition isAutoResolvable pendingRequests

                    hasDbRequests =
                        List.any isDbRequest autoResolvable

                    dbConfigMissing =
                        state.virtualDB.dbConfig == Nothing
                in
                if hasDbRequests && dbConfigMissing then
                    TestError
                        ("Your script uses Pages.Db, but the test was created with fromBackendTask.\n\n"
                            ++ "Use fromBackendTaskWithDb instead to provide DB support:\n\n"
                            ++ "    myScript\n"
                            ++ "        |> BackendTaskTest.fromBackendTaskWithDb Pages.Db.testConfig initialDbValue"
                        )

                else
                    let
                        autoResult =
                            buildAutoResponses state.virtualFS state.virtualDB autoResolvable
                    in
                    case autoResult.error of
                        Just errorMsg ->
                            TestError errorMsg

                        Nothing ->
                            if List.isEmpty external && not (List.isEmpty autoResolvable) then
                                advanceWithAutoResolveHelper (fuel - 1)
                                    { continuation = continuation
                                    , responseEntries = state.responseEntries ++ autoResult.jsonEntries
                                    , responseBytesEntries = Dict.union autoResult.bytesEntries state.responseBytesEntries
                                    , pendingRequests = []
                                    , trackedEffects = state.trackedEffects ++ autoResult.trackedEffects
                                    , virtualFS = autoResult.virtualFS
                                    , virtualDB = autoResult.virtualDB
                                    , simulatedEffects = state.simulatedEffects
                                    }

                            else
                                Running
                                    { continuation = continuation
                                    , responseEntries = state.responseEntries ++ autoResult.jsonEntries
                                    , responseBytesEntries = Dict.union autoResult.bytesEntries state.responseBytesEntries
                                    , pendingRequests = external
                                    , trackedEffects = state.trackedEffects ++ autoResult.trackedEffects
                                    , virtualFS = autoResult.virtualFS
                                    , virtualDB = autoResult.virtualDB
                            , simulatedEffects = state.simulatedEffects
                            }


isAutoResolvable : Request.Request -> Bool
isAutoResolvable request =
    let
        url =
            request.url
    in
    if url == "elm-pages-internal://stream" then
        isStreamAutoResolvable request

    else
        String.startsWith "elm-pages-internal://" url
            && (url /= "elm-pages-internal://port")
            && (url /= "elm-pages-internal://question")
            && (url /= "elm-pages-internal://readKey")


isDbRequest : Request.Request -> Bool
isDbRequest request =
    String.startsWith "elm-pages-internal://db-" request.url


isStreamAutoResolvable : Request.Request -> Bool
isStreamAutoResolvable req =
    case decodeJsonBody streamPipelineDecoder req of
        Just pipeline ->
            List.all isSimulatablePart pipeline.parts

        Nothing ->
            False


type alias StreamPipeline =
    { kind : String
    , parts : List StreamPartInfo
    }


type alias StreamPartInfo =
    { name : String
    , path : Maybe String
    , string : Maybe String
    , command : Maybe String
    , portName : Maybe String
    , url : Maybe String
    }


streamPipelineDecoder : Decode.Decoder StreamPipeline
streamPipelineDecoder =
    Decode.map2 StreamPipeline
        (Decode.field "kind" Decode.string)
        (Decode.field "parts"
            (Decode.list
                (Decode.map6 StreamPartInfo
                    (Decode.field "name" Decode.string)
                    (Decode.maybe (Decode.field "path" Decode.string))
                    (Decode.maybe (Decode.field "string" Decode.string))
                    (Decode.maybe (Decode.field "command" Decode.string))
                    (Decode.maybe (Decode.field "portName" Decode.string))
                    (Decode.maybe (Decode.field "url" Decode.string))
                )
            )
        )


isSimulatablePart : StreamPartInfo -> Bool
isSimulatablePart part =
    case part.name of
        "fileRead" ->
            True

        "fileWrite" ->
            True

        "fromString" ->
            True

        "stdin" ->
            True

        "stdout" ->
            True

        "stderr" ->
            True

        "gzip" ->
            True

        "unzip" ->
            True

        _ ->
            False


type alias AutoResolveResult =
    { jsonEntries : List ( String, Encode.Value )
    , trackedEffects : List TrackedEffect
    , bytesEntries : Dict String Bytes
    , virtualDB : VirtualDB
    , virtualFS : VirtualFS
    , error : Maybe String
    }


buildAutoResponses : VirtualFS -> VirtualDB -> List Request.Request -> AutoResolveResult
buildAutoResponses vfs virtualDB requests =
    List.foldl
        (\req accum ->
            case accum.error of
                Just _ ->
                    accum

                Nothing ->
                    let
                        hash : String
                        hash =
                            Request.hash req
                    in
                    if isDbRequest req then
                        processDbRequest req hash accum

                    else if req.url == "elm-pages-internal://stream" then
                        processStreamRequest req hash accum

                    else if req.url == "elm-pages-internal://make-temp-directory" then
                        processMakeTempDirectory req hash accum

                    else if req.url == "elm-pages-internal://read-file-binary" then
                        processReadFileBinary req hash accum

                    else
                        case autoResponseBody accum.virtualFS req of
                            Err errorMsg ->
                                { accum | error = Just errorMsg }

                            Ok responseBody ->
                                let
                                    responseValue : Encode.Value
                                    responseValue =
                                        Encode.object
                                            [ ( "bodyKind", Encode.string "json" )
                                            , ( "body", responseBody )
                                            ]

                                    entry : ( String, Encode.Value )
                                    entry =
                                        ( hash, Encode.object [ ( "response", responseValue ) ] )

                                    newEffects : List TrackedEffect
                                    newEffects =
                                        trackEffect req

                                in
                                case applyVirtualFSEffect req accum.virtualFS of
                                    Ok newVFS ->
                                        { accum
                                            | jsonEntries = entry :: accum.jsonEntries
                                            , trackedEffects = accum.trackedEffects ++ newEffects
                                            , virtualFS = newVFS
                                        }

                                    Err errorMsg ->
                                        { accum | error = Just errorMsg }
        )
        { jsonEntries = []
        , trackedEffects = []
        , bytesEntries = Dict.empty
        , virtualDB = virtualDB
        , virtualFS = vfs
        , error = Nothing
        }
        requests


autoResponseBody : VirtualFS -> Request.Request -> Result String Encode.Value
autoResponseBody vfs req =
    case req.url of
        "elm-pages-internal://read-file" ->
            case getStringBody req of
                Just rawPath ->
                    let
                        filePath =
                            resolveFilePath req rawPath
                    in
                    case Dict.get filePath vfs.files of
                        Just content ->
                            let
                                { frontmatterValue, bodyWithoutFrontmatter } =
                                    parseFrontmatter content
                            in
                            Ok
                                (Encode.object
                                    [ ( "rawFile", Encode.string content )
                                    , ( "withoutFrontmatter", Encode.string bodyWithoutFrontmatter )
                                    , ( "parsedFrontmatter", frontmatterValue )
                                    ]
                                )

                        Nothing ->
                            Ok
                                (Encode.object
                                    [ ( "errorCode", Encode.string "ENOENT" ) ]
                                )

                Nothing ->
                    Ok Encode.null

        "elm-pages-internal://file-exists" ->
            case req.body of
                StaticHttpBody.JsonBody json ->
                    case Decode.decodeValue Decode.string json of
                        Ok rawPath ->
                            let
                                resolved =
                                    resolveFilePath req rawPath
                            in
                            Ok (Encode.bool (Dict.member resolved vfs.files || Dict.member resolved vfs.binaryFiles))

                        Err _ ->
                            Ok (Encode.bool False)

                _ ->
                    Ok (Encode.bool False)

        "elm-pages-internal://env" ->
            case req.body of
                StaticHttpBody.JsonBody json ->
                    case Decode.decodeValue Decode.string json of
                        Ok envVarName ->
                            let
                                mergedEnv =
                                    Dict.union req.env vfs.env
                            in
                            case Dict.get envVarName mergedEnv of
                                Just value ->
                                    Ok (Encode.string value)

                                Nothing ->
                                    Ok Encode.null

                        Err _ ->
                            Ok Encode.null

                _ ->
                    Ok Encode.null

        "elm-pages-internal://glob" ->
            case decodeJsonBody globRequestDecoder req of
                Just { pattern, options } ->
                    let
                        resolvedCwd =
                            case req.dir of
                                [] ->
                                    ""

                                dirs ->
                                    String.join "/" dirs ++ "/"

                        allFilePaths =
                            Dict.keys vfs.files

                        candidatePaths =
                            let
                                onlyFiles =
                                    options.onlyFiles

                                onlyDirectories =
                                    options.onlyDirectories
                            in
                            if onlyDirectories then
                                Test.GlobMatch.directoriesFromFiles allFilePaths
                                    |> Set.toList

                            else if onlyFiles then
                                allFilePaths

                            else
                                allFilePaths
                                    ++ (Test.GlobMatch.directoriesFromFiles allFilePaths |> Set.toList)

                        -- Make paths relative to cwd for matching
                        relativePaths =
                            if resolvedCwd == "" then
                                candidatePaths

                            else
                                candidatePaths
                                    |> List.filterMap
                                        (\p ->
                                            if String.startsWith resolvedCwd p then
                                                Just (String.dropLeft (String.length resolvedCwd) p)

                                            else
                                                Nothing
                                        )

                        tokens =
                            Test.GlobMatch.parsePattern pattern

                        matchOptions =
                            { caseSensitive = options.caseSensitive
                            , dot = options.dot
                            }

                        matches =
                            Test.GlobMatch.matchPaths matchOptions tokens relativePaths
                    in
                    Ok
                        (matches
                            |> List.map
                                (\{ fullPath, captures } ->
                                    Encode.object
                                        [ ( "fullPath", Encode.string fullPath )
                                        , ( "captures", Encode.list Encode.string captures )
                                        , ( "fileStats"
                                          , Encode.object
                                                [ ( "fullPath", Encode.string fullPath )
                                                , ( "size", Encode.int 0 )
                                                , ( "atime", Encode.int 0 )
                                                , ( "mtime", Encode.int 0 )
                                                , ( "ctime", Encode.int 0 )
                                                , ( "birthtime", Encode.int 0 )
                                                , ( "isDirectory", Encode.bool False )
                                                ]
                                          )
                                        ]
                                )
                            |> Encode.list identity
                        )

                Nothing ->
                    Ok (Encode.list identity [])

        "elm-pages-internal://now" ->
            case vfs.time of
                Just time ->
                    Ok (Encode.int (Time.posixToMillis time))

                Nothing ->
                    Err
                        ("BackendTask.Time.now requires a virtual time.\n\n"
                            ++ "Use withTime in your TestSetup:\n\n"
                            ++ "    BackendTaskTest.defaultSetup\n"
                            ++ "        |> BackendTaskTest.withTime (Time.millisToPosix 1709827200000)"
                        )

        "elm-pages-internal://randomSeed" ->
            case vfs.randomSeed of
                Just seed ->
                    Ok (Encode.int seed)

                Nothing ->
                    Err
                        ("BackendTask.Random requires a virtual random seed.\n\n"
                            ++ "Use withRandomSeed in your TestSetup:\n\n"
                            ++ "    BackendTaskTest.defaultSetup\n"
                            ++ "        |> BackendTaskTest.withRandomSeed 42"
                        )

        "elm-pages-internal://log" ->
            Ok Encode.null

        "elm-pages-internal://write-file" ->
            Ok Encode.null

        "elm-pages-internal://delete-file" ->
            Ok Encode.null

        "elm-pages-internal://copy-file" ->
            Ok Encode.null

        "elm-pages-internal://move" ->
            Ok Encode.null

        "elm-pages-internal://sleep" ->
            Ok Encode.null

        "elm-pages-internal://which" ->
            case decodeJsonBody Decode.string req of
                Just commandName ->
                    case Dict.get commandName vfs.whichCommands of
                        Just path ->
                            Ok (Encode.string path)

                        Nothing ->
                            Ok Encode.null

                Nothing ->
                    Ok Encode.null

        "elm-pages-internal://make-directory" ->
            Ok Encode.null

        "elm-pages-internal://remove-directory" ->
            Ok Encode.null

        "elm-pages-internal://start-spinner" ->
            Ok Encode.null

        "elm-pages-internal://stop-spinner" ->
            Ok Encode.null

        "elm-pages-internal://resolve-path" ->
            case decodeJsonBody Decode.string req of
                Just path ->
                    Ok (Encode.string path)

                Nothing ->
                    Ok Encode.null

        _ ->
            Err
                ("Unsupported elm-pages-internal request: "
                    ++ req.url
                    ++ "\n\nThis request type is not yet supported in the test framework."
                )


globRequestDecoder :
    Decode.Decoder
        { pattern : String
        , options :
            { dot : Bool
            , caseSensitive : Bool
            , onlyFiles : Bool
            , onlyDirectories : Bool
            }
        }
globRequestDecoder =
    Decode.map2
        (\pattern options -> { pattern = pattern, options = options })
        (Decode.field "pattern" Decode.string)
        (Decode.field "options"
            (Decode.map4
                (\dot caseSensitive onlyFiles onlyDirectories ->
                    { dot = dot
                    , caseSensitive = caseSensitive
                    , onlyFiles = onlyFiles
                    , onlyDirectories = onlyDirectories
                    }
                )
                (Decode.field "dot" Decode.bool)
                (Decode.field "caseSensitiveMatch" Decode.bool)
                (Decode.field "onlyFiles" Decode.bool)
                (Decode.field "onlyDirectories" Decode.bool)
            )
        )


resolveStreamPaths : Request.Request -> List StreamPartInfo -> List StreamPartInfo
resolveStreamPaths req parts =
    case req.dir of
        [] ->
            parts

        dirs ->
            let
                resolve path =
                    if String.startsWith "/" path then
                        path

                    else
                        String.join "/" dirs ++ "/" ++ path
            in
            List.map
                (\part -> { part | path = Maybe.map resolve part.path })
                parts


processStreamRequest : Request.Request -> String -> AutoResolveResult -> AutoResolveResult
processStreamRequest req hash accum =
    case decodeJsonBody streamPipelineDecoder req of
        Just pipeline ->
            let
                resolvedParts =
                    resolveStreamPaths req pipeline.parts

                simulationResult =
                    simulateStreamPipeline accum.virtualFS resolvedParts

                responseBody : Encode.Value
                responseBody =
                    case simulationResult.error of
                        Just errorMsg ->
                            Encode.object [ ( "error", Encode.string errorMsg ) ]

                        Nothing ->
                            case pipeline.kind of
                                "text" ->
                                    Encode.object
                                        [ ( "body", Encode.string simulationResult.output )
                                        , ( "metadata", Encode.null )
                                        ]

                                "json" ->
                                    case Decode.decodeString Decode.value simulationResult.output of
                                        Ok jsonValue ->
                                            Encode.object
                                                [ ( "body", jsonValue )
                                                , ( "metadata", Encode.null )
                                                ]

                                        Err _ ->
                                            Encode.object
                                                [ ( "body", Encode.string simulationResult.output )
                                                , ( "metadata", Encode.null )
                                                ]

                                _ ->
                                    -- "none" — Stream.run just needs non-error JSON
                                    Encode.null

                entry : ( String, Encode.Value )
                entry =
                    jsonAutoResolveEntry hash responseBody
            in
            { accum
                | jsonEntries = entry :: accum.jsonEntries
                , trackedEffects = accum.trackedEffects ++ simulationResult.effects
                , virtualFS = simulationResult.virtualFS
            }

        Nothing ->
            let
                entry =
                    jsonAutoResolveEntry hash Encode.null
            in
            { accum | jsonEntries = entry :: accum.jsonEntries }


type alias StreamSimResult =
    { output : String
    , effects : List TrackedEffect
    , virtualFS : VirtualFS
    , error : Maybe String
    }


simulateStreamPipeline : VirtualFS -> List StreamPartInfo -> StreamSimResult
simulateStreamPipeline vfs parts =
    simulateStreamPipelineFrom
        { output = ""
        , effects = []
        , virtualFS = vfs
        , error = Nothing
        }
        parts


getStringBody : Request.Request -> Maybe String
getStringBody req =
    case req.body of
        StaticHttpBody.StringBody _ content ->
            Just content

        _ ->
            Nothing


trackEffect : Request.Request -> List TrackedEffect
trackEffect req =
    case req.url of
        "elm-pages-internal://log" ->
            case req.body of
                StaticHttpBody.JsonBody json ->
                    case Decode.decodeValue (Decode.field "message" Decode.string) json of
                        Ok message ->
                            [ LogEffect message ]

                        Err _ ->
                            []

                _ ->
                    []

        "elm-pages-internal://write-file" ->
            case req.body of
                StaticHttpBody.JsonBody json ->
                    case
                        Decode.decodeValue
                            (Decode.map2 (\p b -> { path = p, body = b })
                                (Decode.field "path" Decode.string)
                                (Decode.field "body" Decode.string)
                            )
                            json
                    of
                        Ok fileWrite ->
                            [ FileWriteEffect { path = resolveFilePath req fileWrite.path, body = fileWrite.body } ]

                        Err _ ->
                            []

                _ ->
                    []

        _ ->
            []


applyVirtualFSEffect : Request.Request -> VirtualFS -> Result String VirtualFS
applyVirtualFSEffect req vfs =
    case req.url of
        "elm-pages-internal://write-file" ->
            case decodeJsonBody (Decode.map2 (\p b -> ( p, b )) (Decode.field "path" Decode.string) (Decode.field "body" Decode.string)) req of
                Just ( rawPath, body ) ->
                    Ok { vfs | files = Dict.insert (resolveFilePath req rawPath) body vfs.files }

                Nothing ->
                    Ok vfs

        "elm-pages-internal://delete-file" ->
            case decodeJsonBody (Decode.field "path" Decode.string) req of
                Just rawPath ->
                    let
                        resolved =
                            resolveFilePath req rawPath
                    in
                    Ok
                        { vfs
                            | files = Dict.remove resolved vfs.files
                            , binaryFiles = Dict.remove resolved vfs.binaryFiles
                        }

                Nothing ->
                    Ok vfs

        "elm-pages-internal://copy-file" ->
            case decodeJsonBody (Decode.map2 Tuple.pair (Decode.field "from" Decode.string) (Decode.field "to" Decode.string)) req of
                Just ( rawFrom, rawTo ) ->
                    let
                        from =
                            resolveFilePath req rawFrom

                        to =
                            resolveFilePath req rawTo
                    in
                    case Dict.get from vfs.files of
                        Just content ->
                            Ok { vfs | files = Dict.insert to content vfs.files }

                        Nothing ->
                            case Dict.get from vfs.binaryFiles of
                                Just content ->
                                    Ok { vfs | binaryFiles = Dict.insert to content vfs.binaryFiles }

                                Nothing ->
                                    Err ("Script.copyFile failed: source file \"" ++ from ++ "\" not found in virtual filesystem.")

                Nothing ->
                    Ok vfs

        "elm-pages-internal://move" ->
            case decodeJsonBody (Decode.map2 Tuple.pair (Decode.field "from" Decode.string) (Decode.field "to" Decode.string)) req of
                Just ( rawFrom, rawTo ) ->
                    let
                        from =
                            resolveFilePath req rawFrom

                        to =
                            resolveFilePath req rawTo
                    in
                    if from == to then
                        Ok vfs

                    else
                        case Dict.get from vfs.files of
                            Just content ->
                                Ok { vfs | files = Dict.insert to content vfs.files |> Dict.remove from }

                            Nothing ->
                                case Dict.get from vfs.binaryFiles of
                                    Just content ->
                                        Ok { vfs | binaryFiles = Dict.insert to content vfs.binaryFiles |> Dict.remove from }

                                    Nothing ->
                                        Err ("Script.move failed: source file \"" ++ from ++ "\" not found in virtual filesystem.")

                Nothing ->
                    Ok vfs

        "elm-pages-internal://remove-directory" ->
            case decodeJsonBody (Decode.field "path" Decode.string) req of
                Just rawPath ->
                    let
                        dirPath =
                            resolveFilePath req rawPath

                        dirPrefix =
                            if String.endsWith "/" dirPath then
                                dirPath

                            else
                                dirPath ++ "/"

                        notInDir : String -> a -> Bool
                        notInDir filePath _ =
                            not (String.startsWith dirPrefix filePath)
                    in
                    Ok
                        { vfs
                            | files = Dict.filter notInDir vfs.files
                            , binaryFiles = Dict.filter notInDir vfs.binaryFiles
                        }

                Nothing ->
                    Ok vfs

        _ ->
            Ok vfs


parseFrontmatter : String -> { frontmatterValue : Encode.Value, bodyWithoutFrontmatter : String }
parseFrontmatter content =
    if String.startsWith "---\n" content then
        case String.indexes "\n---\n" (String.dropLeft 3 content) of
            firstEnd :: _ ->
                let
                    frontmatterString =
                        String.slice 4 (firstEnd + 3) content

                    bodyAfterMarker =
                        String.dropLeft (firstEnd + 3 + 5) content
                in
                case Decode.decodeString Decode.value frontmatterString of
                    Ok jsonValue ->
                        { frontmatterValue = jsonValue
                        , bodyWithoutFrontmatter = bodyAfterMarker
                        }

                    Err _ ->
                        { frontmatterValue = Encode.null
                        , bodyWithoutFrontmatter = bodyAfterMarker
                        }

            [] ->
                { frontmatterValue = Encode.null
                , bodyWithoutFrontmatter = content
                }

    else
        { frontmatterValue = Encode.null
        , bodyWithoutFrontmatter = content
        }


resolveFilePath : Request.Request -> String -> String
resolveFilePath req path =
    case req.dir of
        [] ->
            path

        dirs ->
            if String.startsWith "/" path then
                path

            else
                String.join "/" dirs ++ "/" ++ path


processReadFileBinary : Request.Request -> String -> AutoResolveResult -> AutoResolveResult
processReadFileBinary req hash accum =
    let
        filePath =
            case getStringBody req of
                Just rawPath ->
                    resolveFilePath req rawPath

                Nothing ->
                    ""
    in
    case Dict.get filePath accum.virtualFS.binaryFiles of
        Just fileBytes ->
            let
                responseBytes =
                    BE.encode
                        (BE.sequence
                            [ BE.signedInt32 Bytes.BE (Bytes.width fileBytes)
                            , BE.bytes fileBytes
                            ]
                        )

                jsonEntry =
                    ( hash
                    , Encode.object
                        [ ( "response"
                          , Encode.object
                                [ ( "bodyKind", Encode.string "bytes" ) ]
                          )
                        ]
                    )
            in
            { accum
                | jsonEntries = jsonEntry :: accum.jsonEntries
                , bytesEntries = Dict.insert hash responseBytes accum.bytesEntries
            }

        Nothing ->
            -- Return -1 length to signal file not found (matches Node.js behavior)
            let
                responseBytes =
                    BE.encode (BE.signedInt32 Bytes.BE -1)

                jsonEntry =
                    ( hash
                    , Encode.object
                        [ ( "response"
                          , Encode.object
                                [ ( "bodyKind", Encode.string "bytes" ) ]
                          )
                        ]
                    )
            in
            { accum
                | jsonEntries = jsonEntry :: accum.jsonEntries
                , bytesEntries = Dict.insert hash responseBytes accum.bytesEntries
            }


processMakeTempDirectory : Request.Request -> String -> AutoResolveResult -> AutoResolveResult
processMakeTempDirectory req hash accum =
    let
        prefix =
            case decodeJsonBody Decode.string req of
                Just p ->
                    p

                Nothing ->
                    "tmp-"

        tempPath =
            "/tmp/" ++ prefix ++ String.fromInt accum.virtualFS.tempDirCounter

        currentVFS =
            accum.virtualFS

        updatedVFS =
            { currentVFS | tempDirCounter = currentVFS.tempDirCounter + 1 }

        entry =
            jsonAutoResolveEntry hash (Encode.string tempPath)
    in
    { accum
        | jsonEntries = entry :: accum.jsonEntries
        , virtualFS = updatedVFS
    }


decodeJsonBody : Decode.Decoder a -> Request.Request -> Maybe a
decodeJsonBody decoder req =
    case req.body of
        StaticHttpBody.JsonBody json ->
            Decode.decodeValue decoder json |> Result.toMaybe

        _ ->
            Nothing


processDbRequest : Request.Request -> String -> AutoResolveResult -> AutoResolveResult
processDbRequest req hash accum =
    case req.url of
        "elm-pages-internal://db-lock-acquire" ->
            let
                entry =
                    jsonAutoResolveEntry hash (Encode.string "test-lock-token")
            in
            { accum | jsonEntries = entry :: accum.jsonEntries }

        "elm-pages-internal://db-lock-release" ->
            let
                entry =
                    jsonAutoResolveEntry hash Encode.null
            in
            { accum | jsonEntries = entry :: accum.jsonEntries }

        "elm-pages-internal://db-set-default-path" ->
            let
                entry =
                    jsonAutoResolveEntry hash Encode.null
            in
            { accum | jsonEntries = entry :: accum.jsonEntries }

        "elm-pages-internal://db-read-meta" ->
            let
                responseBytes =
                    constructDbReadMetaBytes accum.virtualDB

                jsonEntry =
                    ( hash
                    , Encode.object
                        [ ( "response"
                          , Encode.object
                                [ ( "bodyKind", Encode.string "bytes" ) ]
                          )
                        ]
                    )
            in
            { accum
                | jsonEntries = jsonEntry :: accum.jsonEntries
                , bytesEntries = Dict.insert hash responseBytes accum.bytesEntries
            }

        "elm-pages-internal://db-write" ->
            let
                newVirtualDB =
                    case extractBytesBody req of
                        Just wire3Bytes ->
                            { state = Just wire3Bytes
                            , dbConfig = accum.virtualDB.dbConfig
                            }

                        Nothing ->
                            accum.virtualDB

                entry =
                    jsonAutoResolveEntry hash Encode.null
            in
            { accum
                | jsonEntries = entry :: accum.jsonEntries
                , virtualDB = newVirtualDB
            }

        "elm-pages-internal://db-migrate-write" ->
            let
                newVirtualDB =
                    case extractBytesBody req of
                        Just wire3Bytes ->
                            { state = Just wire3Bytes
                            , dbConfig = accum.virtualDB.dbConfig
                            }

                        Nothing ->
                            accum.virtualDB

                entry =
                    jsonAutoResolveEntry hash Encode.null
            in
            { accum
                | jsonEntries = entry :: accum.jsonEntries
                , virtualDB = newVirtualDB
            }

        _ ->
            let
                entry =
                    jsonAutoResolveEntry hash Encode.null
            in
            { accum | jsonEntries = entry :: accum.jsonEntries }


jsonAutoResolveEntry : String -> Encode.Value -> ( String, Encode.Value )
jsonAutoResolveEntry hash body =
    ( hash
    , Encode.object
        [ ( "response"
          , Encode.object
                [ ( "bodyKind", Encode.string "json" )
                , ( "body", body )
                ]
          )
        ]
    )


constructDbReadMetaBytes : VirtualDB -> Bytes
constructDbReadMetaBytes virtualDB =
    case ( virtualDB.state, virtualDB.dbConfig ) of
        ( Just wire3, Just config ) ->
            BE.encode
                (BE.sequence
                    [ BE.unsignedInt32 Bytes.BE config.schemaVersion
                    , hexStringToEncoder config.schemaHash
                    , BE.unsignedInt32 Bytes.BE (Bytes.width wire3)
                    , BE.bytes wire3
                    ]
                )

        _ ->
            BE.encode
                (BE.sequence
                    [ BE.unsignedInt32 Bytes.BE 0
                    , BE.sequence (List.repeat 32 (BE.unsignedInt8 0))
                    , BE.unsignedInt32 Bytes.BE 0
                    ]
                )


hexStringToEncoder : String -> BE.Encoder
hexStringToEncoder hex =
    hex
        |> String.toList
        |> pairUp
        |> List.map (\( hi, lo ) -> BE.unsignedInt8 (hexCharToInt hi * 16 + hexCharToInt lo))
        |> padToLength 32
        |> BE.sequence


padToLength : Int -> List BE.Encoder -> List BE.Encoder
padToLength targetLen encoders =
    let
        currentLen =
            List.length encoders
    in
    if currentLen >= targetLen then
        List.take targetLen encoders

    else
        encoders ++ List.repeat (targetLen - currentLen) (BE.unsignedInt8 0)


pairUp : List a -> List ( a, a )
pairUp list =
    case list of
        a :: b :: rest ->
            ( a, b ) :: pairUp rest

        _ ->
            []


hexCharToInt : Char -> Int
hexCharToInt c =
    let
        code =
            Char.toCode c
    in
    if code >= 48 && code <= 57 then
        code - 48

    else if code >= 97 && code <= 102 then
        code - 97 + 10

    else if code >= 65 && code <= 70 then
        code - 65 + 10

    else
        0


extractBytesBody : Request.Request -> Maybe Bytes
extractBytesBody req =
    case req.body of
        StaticHttpBody.BytesBody _ bytes ->
            Just bytes

        _ ->
            Nothing


{-| Simulate a pending HTTP GET request resolving with the given JSON response body.
The URL must exactly match the URL used in `BackendTask.Http.getJson` (or `BackendTask.Http.get`).

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    BackendTask.Http.getJson
        "https://api.github.com/repos/dillonkearns/elm-pages"
        (Decode.field "stargazers_count" Decode.int)
        |> BackendTask.allowFatal
        |> BackendTask.map (\_ -> ())
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpGet
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Encode.object [ ( "stargazers_count", Encode.int 86 ) ])
        |> BackendTaskTest.expectSuccess

If the URL doesn't match any pending request, you'll get a helpful error listing the
actual pending requests.

-}
simulateHttpGet : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateHttpGet url jsonResponse =
    simulateHttpResponse "simulateHttpGet" "GET" url (httpSuccessResponse url jsonResponse)


{-| Simulate a pending HTTP POST request resolving with the given JSON response body.

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    BackendTask.Http.post
        "https://api.example.com/items"
        (BackendTask.Http.jsonBody (Encode.object [ ( "name", Encode.string "test" ) ]))
        (BackendTask.Http.expectJson (Decode.field "id" Decode.int))
        |> BackendTask.allowFatal
        |> BackendTask.map (\_ -> ())
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpPost
            "https://api.example.com/items"
            (Encode.object [ ( "id", Encode.int 42 ) ])
        |> BackendTaskTest.expectSuccess

-}
simulateHttpPost : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateHttpPost url jsonResponse =
    simulateHttpResponse "simulateHttpPost" "POST" url (httpSuccessResponse url jsonResponse)


{-| Simulate a pending HTTP request failing with an [`HttpError`](#HttpError).

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode
    import Test.BackendTask as BackendTaskTest

    BackendTask.Http.getJson
        "https://api.example.com/data"
        (Decode.succeed ())
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpError
            "GET"
            "https://api.example.com/data"
            BackendTaskTest.NetworkError
        |> BackendTaskTest.expectFailure

-}
simulateHttpError : String -> String -> HttpError -> BackendTaskTest a -> BackendTaskTest a
simulateHttpError method url error =
    let
        errorString =
            case error of
                NetworkError ->
                    "NetworkError"

                Timeout ->
                    "Timeout"

        responseValue =
            Encode.object
                [ ( "elm-pages-internal-error", Encode.string errorString ) ]
    in
    simulateHttpResponse "simulateHttpError" method url responseValue


{-| Simulate a pending `BackendTask.Custom.run` call resolving with the given JSON value.
The port name must exactly match the first argument passed to `BackendTask.Custom.run`.

    import BackendTask
    import BackendTask.Custom
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    BackendTask.Custom.run "hashPassword"
        (Encode.string "secret123")
        Decode.string
        |> BackendTask.allowFatal
        |> BackendTask.map (\_ -> ())
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCustom "hashPassword"
            (Encode.string "hashed_secret123")
        |> BackendTaskTest.expectSuccess

-}
simulateCustom : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateCustom portName jsonResponse scriptTest =
    case scriptTest of
        Running state ->
            case findMatchingPort portName state.pendingRequests of
                Just ( matchedReq, remaining ) ->
                    let
                        hash : String
                        hash =
                            Request.hash matchedReq

                        responseValue : Encode.Value
                        responseValue =
                            Encode.object
                                [ ( "bodyKind", Encode.string "json" )
                                , ( "body", jsonResponse )
                                ]

                        entry : ( String, Encode.Value )
                        entry =
                            ( hash, Encode.object [ ( "response", responseValue ) ] )

                        requestBody : Encode.Value
                        requestBody =
                            case matchedReq.body of
                                StaticHttpBody.JsonBody json ->
                                    json

                                _ ->
                                    Encode.null

                        handlerEffects : List SimulatedEffect
                        handlerEffects =
                            case state.simulatedEffects of
                                Just handler ->
                                    handler portName requestBody

                                Nothing ->
                                    []

                        updatedVirtualFS : VirtualFS
                        updatedVirtualFS =
                            applySimulatedEffects handlerEffects state.virtualFS

                        newState : RunningState a
                        newState =
                            { state
                                | responseEntries = entry :: state.responseEntries
                                , pendingRequests = remaining
                                , virtualFS = updatedVirtualFS
                            }
                    in
                    if List.isEmpty remaining then
                        advanceWithAutoResolve newState

                    else
                        Running newState

                Nothing ->
                    TestError
                        ("simulateCustom: Expected a pending BackendTask.Custom.run call for port \""
                            ++ portName
                            ++ "\"\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )

        Done _ ->
            TestError "simulateCustom: The script has already completed. No pending requests to simulate."

        TestError _ ->
            scriptTest


{-| Simulate a pending stream pipeline that contains a `Stream.command`. The framework
handles simulatable parts (`fileRead`, `fileWrite`, `fromString`, `stdin`, `stdout`, `stderr`)
around the command — you only provide the command's output.

    import BackendTask.Stream as Stream
    import Test.BackendTask as BackendTaskTest

    Stream.fromString "input data"
        |> Stream.pipe (Stream.command "grep" [ "error" ])
        |> Stream.pipe (Stream.fileWrite "errors.txt")
        |> Stream.run
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCommand "grep" "error: something bad\n"
        |> BackendTaskTest.ensureFile "errors.txt" "error: something bad\n"
        |> BackendTaskTest.expectSuccess

For `Stream.run` pipelines, the output is used for downstream parts (like `fileWrite`)
but isn't returned to Elm. For `Stream.read`, it becomes the body.

-}
simulateCommand : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateCommand commandName commandOutput scriptTest =
    simulateStreamByPartName "simulateCommand"
        (\part -> part.name == "command" && part.command == Just commandName)
        ("command \"" ++ commandName ++ "\"")
        commandMetadata
        commandOutput
        scriptTest


commandMetadata : Encode.Value
commandMetadata =
    Encode.object [ ( "exitCode", Encode.int 0 ) ]


{-| Simulate a pending stream pipeline that contains a custom stream part (`Stream.customRead`,
`Stream.customWrite`, or `Stream.customDuplex`). Works like `simulateCommand` — the framework
handles simulatable parts around the custom port, you only provide the port's output.

    Stream.fromString "input"
        |> Stream.pipe (Stream.customDuplex "myTransform" (Encode.object []))
        |> Stream.pipe (Stream.fileWrite "output.txt")
        |> Stream.run
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCustomStream "myTransform" "transformed output"
        |> BackendTaskTest.ensureFile "output.txt" "transformed output"
        |> BackendTaskTest.expectSuccess

-}
simulateCustomStream : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateCustomStream portName portOutput scriptTest =
    simulateStreamByPartName "simulateCustomStream"
        (\part -> part.portName == Just portName)
        ("custom stream port \"" ++ portName ++ "\"")
        commandMetadata
        portOutput
        scriptTest


{-| Simulate a pending stream pipeline that contains an HTTP stream part (`Stream.http` or
`Stream.httpWithInput`). Works like `simulateCommand` — the framework handles simulatable parts
around the HTTP request, you only provide the response body.

    Stream.fromString "request body"
        |> Stream.pipe (Stream.httpWithInput { url = "https://api.example.com", method = "POST", headers = [], retries = 0, timeoutInMs = 0 })
        |> Stream.read
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateStreamHttp "https://api.example.com" "response body"
        |> BackendTaskTest.expectSuccess

-}
simulateStreamHttp : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateStreamHttp url httpOutput scriptTest =
    simulateStreamByPartName "simulateStreamHttp"
        (\part -> part.url == Just url)
        ("stream HTTP request \"" ++ url ++ "\"")
        (httpStreamMetadata url)
        httpOutput
        scriptTest


httpStreamMetadata : String -> Encode.Value
httpStreamMetadata url =
    Encode.object
        [ ( "statusCode", Encode.int 200 )
        , ( "statusText", Encode.string "OK" )
        , ( "headers", Encode.object [] )
        , ( "url", Encode.string url )
        ]


{-| Simulate a pending `Script.question` call resolving with the given answer.
The prompt must match the prompt text passed to `Script.question`.

    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.question "What is your name? "
        |> BackendTask.andThen
            (\name -> Script.log ("Hello, " ++ name ++ "!"))
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateQuestion "What is your name? " "Dillon"
        |> BackendTaskTest.ensureLogged "Hello, Dillon!"
        |> BackendTaskTest.expectSuccess

-}
simulateQuestion : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateQuestion prompt answer scriptTest =
    simulateInteractive "simulateQuestion" "question" (matchByPrompt prompt) ("question \"" ++ prompt ++ "\"") answer scriptTest


{-| Simulate a pending `Script.readKey` call resolving with the given key.

    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.readKey
        |> BackendTask.andThen
            (\key ->
                if key == "y" then
                    Script.log "confirmed"
                else
                    Script.log "rejected"
            )
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateReadKey "y"
        |> BackendTaskTest.ensureLogged "confirmed"
        |> BackendTaskTest.expectSuccess

-}
simulateReadKey : String -> BackendTaskTest a -> BackendTaskTest a
simulateReadKey key scriptTest =
    simulateInteractive "simulateReadKey" "readKey" (\_ -> True) "readKey" key scriptTest


matchByPrompt : String -> Request.Request -> Bool
matchByPrompt expectedPrompt req =
    case decodeJsonBody (Decode.field "prompt" Decode.string) req of
        Just actualPrompt ->
            actualPrompt == expectedPrompt

        Nothing ->
            False


simulateInteractive : String -> String -> (Request.Request -> Bool) -> String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateInteractive callerName urlSuffix predicate description answer scriptTest =
    let
        targetUrl =
            "elm-pages-internal://" ++ urlSuffix
    in
    case scriptTest of
        Running state ->
            case findMatchingInteractive targetUrl predicate state.pendingRequests of
                Just ( matchedReq, remaining ) ->
                    let
                        hash =
                            Request.hash matchedReq

                        responseValue =
                            Encode.object
                                [ ( "bodyKind", Encode.string "json" )
                                , ( "body", Encode.string answer )
                                ]

                        entry =
                            ( hash, Encode.object [ ( "response", responseValue ) ] )

                        newState =
                            { state
                                | responseEntries = entry :: state.responseEntries
                                , pendingRequests = remaining
                            }
                    in
                    if List.isEmpty remaining then
                        advanceWithAutoResolve newState

                    else
                        Running newState

                Nothing ->
                    TestError
                        (callerName
                            ++ ": Expected a pending "
                            ++ description
                            ++ "\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )

        Done _ ->
            TestError (callerName ++ ": The script has already completed. No pending requests to simulate.")

        TestError _ ->
            scriptTest


findMatchingInteractive : String -> (Request.Request -> Bool) -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingInteractive targetUrl predicate requests =
    findMatchingInteractiveHelper targetUrl predicate [] requests


findMatchingInteractiveHelper : String -> (Request.Request -> Bool) -> List Request.Request -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingInteractiveHelper targetUrl predicate before after =
    case after of
        [] ->
            Nothing

        req :: rest ->
            if req.url == targetUrl && predicate req then
                Just ( req, List.reverse before ++ rest )

            else
                findMatchingInteractiveHelper targetUrl predicate (req :: before) rest


{-| Internal helper — shared implementation for simulateCommand, simulateCustomStream, simulateStreamHttp.
-}
simulateStreamByPartName : String -> (StreamPartInfo -> Bool) -> String -> Encode.Value -> String -> BackendTaskTest a -> BackendTaskTest a
simulateStreamByPartName callerName predicate description metadata opaqueOutput scriptTest =
    case scriptTest of
        Running state ->
            case findMatchingStreamByPart predicate state.pendingRequests of
                Just ( matchedReq, remaining ) ->
                    let
                        hash : String
                        hash =
                            Request.hash matchedReq
                    in
                    case decodeJsonBody streamPipelineDecoder matchedReq of
                        Just pipeline ->
                            let
                                resolvedParts =
                                    resolveStreamPaths matchedReq pipeline.parts

                                simResult =
                                    simulateStreamWithOpaquePart predicate state.virtualFS opaqueOutput resolvedParts

                                responseBody : Encode.Value
                                responseBody =
                                    case simResult.error of
                                        Just errorMsg ->
                                            Encode.object [ ( "error", Encode.string errorMsg ) ]

                                        Nothing ->
                                            case pipeline.kind of
                                                "text" ->
                                                    Encode.object
                                                        [ ( "body", Encode.string simResult.output )
                                                        , ( "metadata", metadata )
                                                        ]

                                                "json" ->
                                                    case Decode.decodeString Decode.value simResult.output of
                                                        Ok jsonValue ->
                                                            Encode.object
                                                                [ ( "body", jsonValue )
                                                                , ( "metadata", metadata )
                                                                ]

                                                        Err _ ->
                                                            Encode.object
                                                                [ ( "body", Encode.string simResult.output )
                                                                , ( "metadata", metadata )
                                                                ]

                                                _ ->
                                                    Encode.null

                                entry : ( String, Encode.Value )
                                entry =
                                    jsonAutoResolveEntry hash responseBody

                                newState : RunningState a
                                newState =
                                    { state
                                        | responseEntries = entry :: state.responseEntries
                                        , pendingRequests = remaining
                                        , virtualFS = simResult.virtualFS
                                        , trackedEffects = state.trackedEffects ++ simResult.effects
                                    }
                            in
                            if List.isEmpty remaining then
                                advanceWithAutoResolve newState

                            else
                                Running newState

                        Nothing ->
                            TestError (callerName ++ ": Failed to decode stream pipeline.")

                Nothing ->
                    TestError
                        (callerName
                            ++ ": Expected a pending stream with "
                            ++ description
                            ++ "\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )

        Done _ ->
            TestError (callerName ++ ": The script has already completed. No pending requests to simulate.")

        TestError _ ->
            scriptTest


findMatchingStreamByPart : (StreamPartInfo -> Bool) -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingStreamByPart predicate requests =
    findMatchingStreamByPartHelper predicate [] requests


findMatchingStreamByPartHelper : (StreamPartInfo -> Bool) -> List Request.Request -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingStreamByPartHelper predicate before after =
    case after of
        [] ->
            Nothing

        req :: rest ->
            if req.url == "elm-pages-internal://stream" && streamHasPart predicate req then
                Just ( req, List.reverse before ++ rest )

            else
                findMatchingStreamByPartHelper predicate (req :: before) rest


streamHasPart : (StreamPartInfo -> Bool) -> Request.Request -> Bool
streamHasPart predicate req =
    case decodeJsonBody streamPipelineDecoder req of
        Just pipeline ->
            List.any predicate pipeline.parts

        Nothing ->
            False


simulateStreamWithOpaquePart : (StreamPartInfo -> Bool) -> VirtualFS -> String -> List StreamPartInfo -> StreamSimResult
simulateStreamWithOpaquePart predicate vfs opaqueOutput parts =
    let
        ( before, afterIncluding ) =
            splitAtPart predicate parts

        after =
            List.drop 1 afterIncluding

        beforeResult =
            simulateStreamPipeline vfs before
    in
    case beforeResult.error of
        Just _ ->
            beforeResult

        Nothing ->
            let
                afterResult =
                    simulateStreamPipelineFrom
                        { output = opaqueOutput
                        , effects = []
                        , virtualFS = beforeResult.virtualFS
                        , error = Nothing
                        }
                        after
            in
            { afterResult
                | effects = beforeResult.effects ++ afterResult.effects
            }


splitAtPart : (StreamPartInfo -> Bool) -> List StreamPartInfo -> ( List StreamPartInfo, List StreamPartInfo )
splitAtPart predicate parts =
    splitAtPartHelper predicate [] parts


splitAtPartHelper : (StreamPartInfo -> Bool) -> List StreamPartInfo -> List StreamPartInfo -> ( List StreamPartInfo, List StreamPartInfo )
splitAtPartHelper predicate before after =
    case after of
        [] ->
            ( List.reverse before, [] )

        part :: rest ->
            if predicate part then
                ( List.reverse before, part :: rest )

            else
                splitAtPartHelper predicate (part :: before) rest


simulateStreamPipelineFrom : StreamSimResult -> List StreamPartInfo -> StreamSimResult
simulateStreamPipelineFrom initial parts =
    List.foldl
        (\part accum ->
            case accum.error of
                Just _ ->
                    accum

                Nothing ->
                    case part.name of
                        "fromString" ->
                            { accum | output = Maybe.withDefault "" part.string }

                        "stdin" ->
                            case accum.virtualFS.stdin of
                                Just content ->
                                    { accum | output = content }

                                Nothing ->
                                    { accum | error = Just "Stream stdin: No stdin content provided. Use withStdin in your TestSetup." }

                        "fileRead" ->
                            case part.path of
                                Just path ->
                                    case Dict.get path accum.virtualFS.files of
                                        Just content ->
                                            { accum | output = content }

                                        Nothing ->
                                            { accum | error = Just ("Stream fileRead: File \"" ++ path ++ "\" not found in virtual filesystem.") }

                                Nothing ->
                                    accum

                        "fileWrite" ->
                            case part.path of
                                Just path ->
                                    { accum
                                        | virtualFS = insertFile path accum.output accum.virtualFS
                                        , effects = accum.effects ++ [ FileWriteEffect { path = path, body = accum.output } ]
                                    }

                                Nothing ->
                                    accum

                        "stdout" ->
                            { accum | effects = accum.effects ++ [ StdoutEffect accum.output ] }

                        "stderr" ->
                            { accum | effects = accum.effects ++ [ StderrEffect accum.output ] }

                        "gzip" ->
                            { accum | output = gzipMarker ++ accum.output }

                        "unzip" ->
                            if String.startsWith gzipMarker accum.output then
                                { accum | output = String.dropLeft (String.length gzipMarker) accum.output }

                            else
                                { accum | error = Just "Stream unzip: Data is not gzipped. In tests, only data that passed through a gzip stream part can be unzipped." }

                        _ ->
                            accum
        )
        initial
        parts


gzipMarker : String
gzipMarker =
    "****GZIPPED****"


httpSuccessResponse : String -> Encode.Value -> Encode.Value
httpSuccessResponse url jsonResponse =
    Encode.object
        [ ( "statusCode", Encode.int 200 )
        , ( "statusText", Encode.string "OK" )
        , ( "headers", Encode.object [] )
        , ( "url", Encode.string url )
        , ( "bodyKind", Encode.string "json" )
        , ( "body", jsonResponse )
        ]


simulateHttpResponse : String -> String -> String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateHttpResponse callerName method url responseValue scriptTest =
    case scriptTest of
        Running state ->
            case findMatchingRequest method url state.pendingRequests of
                Just ( matchedReq, remaining ) ->
                    let
                        hash =
                            Request.hash matchedReq

                        entry =
                            ( hash, Encode.object [ ( "response", responseValue ) ] )

                        newState =
                            { state
                                | responseEntries = entry :: state.responseEntries
                                , pendingRequests = remaining
                            }
                    in
                    if List.isEmpty remaining then
                        advanceWithAutoResolve newState

                    else
                        Running newState

                Nothing ->
                    TestError
                        (callerName
                            ++ ": Expected a pending "
                            ++ method
                            ++ " request for\n\n    "
                            ++ url
                            ++ "\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )

        Done _ ->
            TestError (callerName ++ ": The script has already completed. No pending requests to simulate.")

        TestError _ ->
            scriptTest


findMatchingRequest : String -> String -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingRequest method url requests =
    findMatchingRequestHelper method url [] requests


findMatchingRequestHelper : String -> String -> List Request.Request -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingRequestHelper method url before after =
    case after of
        [] ->
            Nothing

        req :: rest ->
            if req.method == method && req.url == url then
                Just ( req, List.reverse before ++ rest )

            else
                findMatchingRequestHelper method url (req :: before) rest


findMatchingPort : String -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingPort portName requests =
    findMatchingPortHelper portName [] requests


findMatchingPortHelper : String -> List Request.Request -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingPortHelper portName before after =
    case after of
        [] ->
            Nothing

        req :: rest ->
            if req.url == "elm-pages-internal://port" && getPortName req == Just portName then
                Just ( req, List.reverse before ++ rest )

            else
                findMatchingPortHelper portName (req :: before) rest


getPortName : Request.Request -> Maybe String
getPortName req =
    case req.body of
        StaticHttpBody.JsonBody json ->
            Decode.decodeValue (Decode.field "portName" Decode.string) json
                |> Result.toMaybe

        _ ->
            Nothing


formatPendingRequests : List Request.Request -> String
formatPendingRequests requests =
    if List.isEmpty requests then
        "    (none)"

    else
        requests
            |> List.map
                (\req ->
                    if req.url == "elm-pages-internal://port" then
                        "    BackendTask.Custom.run \"" ++ (getPortName req |> Maybe.withDefault "???") ++ "\""

                    else if req.url == "elm-pages-internal://stream" then
                        "    Stream [" ++ formatStreamParts req ++ "]"

                    else if req.url == "elm-pages-internal://question" then
                        case decodeJsonBody (Decode.field "prompt" Decode.string) req of
                            Just prompt ->
                                "    Script.question \"" ++ prompt ++ "\""

                            Nothing ->
                                "    Script.question ???"

                    else if req.url == "elm-pages-internal://readKey" then
                        "    Script.readKey"

                    else
                        "    " ++ req.method ++ " " ++ req.url
                )
            |> String.join "\n"


formatStreamParts : Request.Request -> String
formatStreamParts req =
    case decodeJsonBody (Decode.field "parts" (Decode.list (Decode.field "name" Decode.string))) req of
        Just parts ->
            String.join " | " parts

        Nothing ->
            "???"


{-| Assert that a GET request to the given URL is currently pending, without resolving it.
This is useful for verifying that requests are issued in parallel — if both `ensureHttpGet`
calls pass, you know `map2` (or `combine`) dispatched them at the same time rather than
sequentially.

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    BackendTask.map2 (\_ _ -> ())
        (BackendTask.Http.getJson
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Decode.field "stargazers_count" Decode.int)
            |> BackendTask.allowFatal
        )
        (BackendTask.Http.getJson
            "https://api.github.com/repos/dillonkearns/elm-graphql"
            (Decode.field "stargazers_count" Decode.int)
            |> BackendTask.allowFatal
        )
        |> BackendTaskTest.fromBackendTask
        -- verify both requests are pending at the same time
        |> BackendTaskTest.ensureHttpGet
            "https://api.github.com/repos/dillonkearns/elm-pages"
        |> BackendTaskTest.ensureHttpGet
            "https://api.github.com/repos/dillonkearns/elm-graphql"
        |> BackendTaskTest.simulateHttpGet
            "https://api.github.com/repos/dillonkearns/elm-pages"
            (Encode.object [ ( "stargazers_count", Encode.int 1205 ) ])
        |> BackendTaskTest.simulateHttpGet
            "https://api.github.com/repos/dillonkearns/elm-graphql"
            (Encode.object [ ( "stargazers_count", Encode.int 780 ) ])
        |> BackendTaskTest.expectSuccess

Note: you don't need `ensureHttpGet` before every `simulateHttpGet` —
`simulateHttpGet` already fails if the request isn't pending. Use `ensure`
when you want to verify request timing (parallel vs sequential).

-}
ensureHttpGet : String -> BackendTaskTest a -> BackendTaskTest a
ensureHttpGet url =
    ensureHttpRequest "ensureHttpGet" "GET" url


{-| Assert that a POST request to the given URL is currently pending, without resolving it.
Like [`ensureHttpGet`](#ensureHttpGet), this is most useful for verifying request timing.

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    -- Verify that a GET and POST are issued in parallel
    BackendTask.map2 (\_ _ -> ())
        (BackendTask.Http.getJson
            "https://api.example.com/config"
            (Decode.succeed ())
            |> BackendTask.allowFatal
        )
        (BackendTask.Http.post
            "https://api.example.com/items"
            (BackendTask.Http.jsonBody (Encode.object [ ( "name", Encode.string "test" ) ]))
            (BackendTask.Http.expectJson (Decode.succeed ()))
            |> BackendTask.allowFatal
        )
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureHttpGet "https://api.example.com/config"
        |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
        |> BackendTaskTest.simulateHttpGet "https://api.example.com/config" Encode.null
        |> BackendTaskTest.simulateHttpPost "https://api.example.com/items" Encode.null
        |> BackendTaskTest.expectSuccess

-}
ensureHttpPost : String -> BackendTaskTest a -> BackendTaskTest a
ensureHttpPost url =
    ensureHttpRequest "ensureHttpPost" "POST" url


ensureHttpRequest : String -> String -> String -> BackendTaskTest a -> BackendTaskTest a
ensureHttpRequest callerName method url scriptTest =
    case scriptTest of
        TestError _ ->
            scriptTest

        Done _ ->
            TestError
                (callerName
                    ++ ": Expected a pending "
                    ++ method
                    ++ " request for\n\n    "
                    ++ url
                    ++ "\n\nbut the script has already completed."
                )

        Running state ->
            case findMatchingRequest method url state.pendingRequests of
                Just _ ->
                    scriptTest

                Nothing ->
                    TestError
                        (callerName
                            ++ ": Expected a pending "
                            ++ method
                            ++ " request for\n\n    "
                            ++ url
                            ++ "\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )


{-| Assert that a `BackendTask.Custom.run` call with the given port name is currently pending,
without resolving it. Like [`ensureHttpGet`](#ensureHttpGet), this is most useful for
verifying that calls are issued in parallel.

    import BackendTask
    import BackendTask.Custom
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    -- Verify both custom calls are dispatched in parallel
    BackendTask.map2 (\_ _ -> ())
        (BackendTask.Custom.run "hashPassword"
            (Encode.string "secret123")
            Decode.string
            |> BackendTask.allowFatal
        )
        (BackendTask.Custom.run "sendEmail"
            (Encode.string "user@example.com")
            (Decode.succeed ())
            |> BackendTask.allowFatal
        )
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureCustom "hashPassword"
        |> BackendTaskTest.ensureCustom "sendEmail"
        |> BackendTaskTest.simulateCustom "hashPassword"
            (Encode.string "hashed_secret123")
        |> BackendTaskTest.simulateCustom "sendEmail"
            Encode.null
        |> BackendTaskTest.expectSuccess

-}
ensureCustom : String -> BackendTaskTest a -> BackendTaskTest a
ensureCustom portName scriptTest =
    case scriptTest of
        TestError _ ->
            scriptTest

        Done _ ->
            TestError
                ("ensureCustom: Expected a pending BackendTask.Custom.run call for port \""
                    ++ portName
                    ++ "\"\n\nbut the script has already completed."
                )

        Running state ->
            case findMatchingPort portName state.pendingRequests of
                Just _ ->
                    scriptTest

                Nothing ->
                    TestError
                        ("ensureCustom: Expected a pending BackendTask.Custom.run call for port \""
                            ++ portName
                            ++ "\"\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )


{-| Assert that the given message was logged via `Script.log`. Can be used at any point
in the pipeline — it checks all log messages that have occurred so far.

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.log "Hello, World!"
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureLogged "Hello, World!"
        |> BackendTaskTest.expectSuccess

-}
ensureLogged : String -> BackendTaskTest a -> BackendTaskTest a
ensureLogged expectedMessage scriptTest =
    case scriptTest of
        TestError _ ->
            scriptTest

        Done state ->
            if List.member (LogEffect expectedMessage) state.trackedEffects then
                scriptTest

            else
                TestError
                    ("ensureLogged: Expected a log message:\n\n    \""
                        ++ expectedMessage
                        ++ "\"\n\nbut the logged messages are:\n\n"
                        ++ formatLoggedMessages state.trackedEffects
                    )

        Running state ->
            if List.member (LogEffect expectedMessage) state.trackedEffects then
                scriptTest

            else
                TestError
                    ("ensureLogged: Expected a log message:\n\n    \""
                        ++ expectedMessage
                        ++ "\"\n\nbut the logged messages are:\n\n"
                        ++ formatLoggedMessages state.trackedEffects
                    )


{-| Assert that a file was written with the given path and body via `Script.writeFile`.
Both the path and body must match exactly.

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.writeFile { path = "output.json", body = """{"key":"value"}""" }
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureFileWritten
            { path = "output.json", body = """{"key":"value"}""" }
        |> BackendTaskTest.expectSuccess

-}
ensureFileWritten : { path : String, body : String } -> BackendTaskTest a -> BackendTaskTest a
ensureFileWritten expected scriptTest =
    let
        check effects =
            if List.member (FileWriteEffect expected) effects then
                scriptTest

            else
                TestError
                    ("ensureFileWritten: Expected a file write to:\n\n    "
                        ++ expected.path
                        ++ "\n\nbut the file writes are:\n\n"
                        ++ formatFileWrites effects
                    )
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Done state ->
            check state.trackedEffects

        Running state ->
            check state.trackedEffects


{-| Assert that the given content was written to stdout via a stream pipeline
(e.g., `Stream.fromString "hello" |> Stream.pipe Stream.stdout |> Stream.run`).

    import BackendTask.Stream as Stream
    import Test.BackendTask as BackendTaskTest

    Stream.fromString "hello"
        |> Stream.pipe Stream.stdout
        |> Stream.run
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureStdout "hello"
        |> BackendTaskTest.expectSuccess

-}
ensureStdout : String -> BackendTaskTest a -> BackendTaskTest a
ensureStdout expectedContent scriptTest =
    let
        check effects =
            if List.member (StdoutEffect expectedContent) effects then
                scriptTest

            else
                TestError
                    ("ensureStdout: Expected stdout output:\n\n    \""
                        ++ expectedContent
                        ++ "\"\n\nbut the stdout outputs are:\n\n"
                        ++ formatStdOutputs StdoutEffect effects
                    )
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Done state ->
            check state.trackedEffects

        Running state ->
            check state.trackedEffects


{-| Assert that the given content was written to stderr via a stream pipeline.

    import BackendTask.Stream as Stream
    import Test.BackendTask as BackendTaskTest

    Stream.fromString "error!"
        |> Stream.pipe Stream.stderr
        |> Stream.run
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureStderr "error!"
        |> BackendTaskTest.expectSuccess

-}
ensureStderr : String -> BackendTaskTest a -> BackendTaskTest a
ensureStderr expectedContent scriptTest =
    let
        check effects =
            if List.member (StderrEffect expectedContent) effects then
                scriptTest

            else
                TestError
                    ("ensureStderr: Expected stderr output:\n\n    \""
                        ++ expectedContent
                        ++ "\"\n\nbut the stderr outputs are:\n\n"
                        ++ formatStdOutputs StderrEffect effects
                    )
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Done state ->
            check state.trackedEffects

        Running state ->
            check state.trackedEffects


formatStdOutputs : (String -> TrackedEffect) -> List TrackedEffect -> String
formatStdOutputs constructor effects =
    let
        outputs =
            List.filterMap
                (\effect ->
                    case ( effect, constructor "" ) of
                        ( StdoutEffect content, StdoutEffect _ ) ->
                            Just ("    \"" ++ content ++ "\"")

                        ( StderrEffect content, StderrEffect _ ) ->
                            Just ("    \"" ++ content ++ "\"")

                        _ ->
                            Nothing
                )
                effects
    in
    if List.isEmpty outputs then
        "    (none)"

    else
        String.join "\n" outputs


formatFileWrites : List TrackedEffect -> String
formatFileWrites effects =
    let
        writes =
            List.filterMap
                (\effect ->
                    case effect of
                        FileWriteEffect { path } ->
                            Just ("    " ++ path)

                        _ ->
                            Nothing
                )
                effects
    in
    if List.isEmpty writes then
        "    (none)"

    else
        String.join "\n" writes


formatLoggedMessages : List TrackedEffect -> String
formatLoggedMessages effects =
    let
        logMessages =
            List.filterMap
                (\effect ->
                    case effect of
                        LogEffect msg ->
                            Just ("    \"" ++ msg ++ "\"")

                        _ ->
                            Nothing
                )
                effects
    in
    if List.isEmpty logMessages then
        "    (none)"

    else
        String.join "\n" logMessages


insertFile : String -> String -> VirtualFS -> VirtualFS
insertFile path content vfs =
    { vfs | files = Dict.insert path content vfs.files }


{-| Assert that a file exists in the virtual filesystem with the given content.
This checks the end state — all `Script.writeFile` calls that have been auto-resolved
so far will be reflected.

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.writeFile { path = "output.txt", body = "hello" }
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureFile "output.txt" "hello"
        |> BackendTaskTest.expectSuccess

-}
ensureFile : String -> String -> BackendTaskTest a -> BackendTaskTest a
ensureFile path expectedContent scriptTest =
    let
        checkFS : VirtualFS -> BackendTaskTest a
        checkFS vfs =
            case Dict.get path vfs.files of
                Just actualContent ->
                    if actualContent == expectedContent then
                        scriptTest

                    else
                        TestError
                            ("ensureFile: File \"" ++ path ++ "\" exists but has different content.\n\nExpected:\n\n    " ++ expectedContent ++ "\n\nActual:\n\n    " ++ actualContent)

                Nothing ->
                    TestError
                        ("ensureFile: Expected file \"" ++ path ++ "\" to exist but it was not found.\n\nFiles in virtual filesystem:\n\n" ++ formatVirtualFiles vfs)
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Running state ->
            checkFS state.virtualFS

        Done state ->
            checkFS state.virtualFS


{-| Assert that a file exists in the virtual filesystem (without checking its content).

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.writeFile { path = "output.txt", body = "hello" }
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureFileExists "output.txt"
        |> BackendTaskTest.expectSuccess

-}
ensureFileExists : String -> BackendTaskTest a -> BackendTaskTest a
ensureFileExists path scriptTest =
    let
        checkFS : VirtualFS -> BackendTaskTest a
        checkFS vfs =
            case Dict.get path vfs.files of
                Just _ ->
                    scriptTest

                Nothing ->
                    TestError
                        ("ensureFileExists: Expected file \"" ++ path ++ "\" to exist but it was not found.\n\nFiles in virtual filesystem:\n\n" ++ formatVirtualFiles vfs)
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Running state ->
            checkFS state.virtualFS

        Done state ->
            checkFS state.virtualFS


{-| Assert that a file does not exist in the virtual filesystem. Useful for verifying
that a file was deleted or was never created.

    import BackendTask
    import Test.BackendTask as BackendTaskTest

    BackendTask.succeed ()
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureNoFile "output.txt"
        |> BackendTaskTest.expectSuccess

-}
ensureNoFile : String -> BackendTaskTest a -> BackendTaskTest a
ensureNoFile path scriptTest =
    let
        checkFS : VirtualFS -> BackendTaskTest a
        checkFS vfs =
            case Dict.get path vfs.files of
                Just _ ->
                    TestError ("ensureNoFile: Expected file \"" ++ path ++ "\" to not exist but it was found.")

                Nothing ->
                    scriptTest
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Running state ->
            checkFS state.virtualFS

        Done state ->
            checkFS state.virtualFS


{-| Declare filesystem side effects for custom ports. The handler receives the port name
and the request body (as JSON), and returns a list of [`SimulatedEffect`](#SimulatedEffect)s
to apply to the virtual filesystem when the port is resolved via [`simulateCustom`](#simulateCustom).

This follows the same pattern as elm-program-test's `withSimulatedEffects` — it's a
translation layer, not an auto-resolver. Custom ports still pause and require explicit
[`simulateCustom`](#simulateCustom) calls.

    import BackendTask
    import BackendTask.Custom
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    BackendTask.Custom.run "generateReport"
        (Encode.string "input")
        (Decode.succeed ())
        |> BackendTask.allowFatal
        |> BackendTask.map (\_ -> ())
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.withSimulatedEffects
            (\portName _ ->
                case portName of
                    "generateReport" ->
                        [ BackendTaskTest.writeFileEffect "report.pdf" "content" ]

                    _ ->
                        []
            )
        |> BackendTaskTest.simulateCustom "generateReport" Encode.null
        |> BackendTaskTest.ensureFile "report.pdf" "content"
        |> BackendTaskTest.expectSuccess

-}
withSimulatedEffects : (String -> Encode.Value -> List SimulatedEffect) -> BackendTaskTest a -> BackendTaskTest a
withSimulatedEffects handler scriptTest =
    case scriptTest of
        Running state ->
            Running { state | simulatedEffects = Just handler }

        _ ->
            scriptTest


{-| Declare that a custom port writes a file to the virtual filesystem.

    BackendTaskTest.writeFileEffect "output.txt" "file content"

-}
writeFileEffect : String -> String -> SimulatedEffect
writeFileEffect path body =
    SimWriteFile { path = path, body = body }


{-| Declare that a custom port removes a file from the virtual filesystem.

    BackendTaskTest.removeFileEffect "temp.txt"

-}
removeFileEffect : String -> SimulatedEffect
removeFileEffect path =
    SimRemoveFile path


applySimulatedEffects : List SimulatedEffect -> VirtualFS -> VirtualFS
applySimulatedEffects effects vfs =
    List.foldl applySimulatedEffect vfs effects


applySimulatedEffect : SimulatedEffect -> VirtualFS -> VirtualFS
applySimulatedEffect effect vfs =
    case effect of
        SimWriteFile { path, body } ->
            { vfs | files = Dict.insert path body vfs.files }

        SimRemoveFile path ->
            { vfs | files = Dict.remove path vfs.files }


formatVirtualFiles : VirtualFS -> String
formatVirtualFiles vfs =
    let
        filePaths : List String
        filePaths =
            Dict.keys vfs.files
                |> List.map (\p -> "    " ++ p)
    in
    if List.isEmpty filePaths then
        "    (none)"

    else
        String.join "\n" filePaths


permanentErrorToString : Pages.StaticHttpRequest.Error -> String
permanentErrorToString err =
    case err of
        Pages.StaticHttpRequest.DecoderError msg ->
            "Decoder error: " ++ msg

        Pages.StaticHttpRequest.UserCalledStaticHttpFail msg ->
            msg

        Pages.StaticHttpRequest.InternalFailure _ ->
            "Internal error"


fatalErrorToString : FatalError -> String
fatalErrorToString error =
    case error of
        Pages.Internal.FatalError.FatalError { title, body } ->
            title ++ "\n\n" ++ body


{-| Assert that the `BackendTask` completed successfully. This is a terminal assertion —
it produces an `Expectation` for elm-test, so it should be the last step in your pipeline.

    import BackendTask
    import Test.BackendTask as BackendTaskTest

    BackendTask.succeed ()
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

If the `BackendTask` still has pending requests, the test fails with a message listing them.

-}
expectSuccess : BackendTaskTest a -> Expectation
expectSuccess scriptTest =
    case scriptTest of
        Done { result } ->
            case result of
                Ok _ ->
                    Expect.pass

                Err err ->
                    Expect.fail ("Expected success but the script failed with an error:\n\n" ++ fatalErrorToString err)

        Running state ->
            Expect.fail
                ("Expected the script to complete, but there are still pending requests:\n\n"
                    ++ formatPendingRequests state.pendingRequests
                )

        TestError msg ->
            Expect.fail msg


{-| Like [`expectSuccess`](#expectSuccess), but also runs an assertion on the
result value. Use this when your `BackendTask` returns a value you want to check
with elm-test assertions.

    import BackendTask.Glob as Glob
    import Test.BackendTask as BackendTaskTest

    Glob.fromString "content/blog/*.md"
        |> BackendTask.map List.sort
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.defaultSetup
                |> BackendTaskTest.withFile "content/blog/first-post.md" "First"
                |> BackendTaskTest.withFile "content/blog/second-post.md" "Second"
            )
        |> BackendTaskTest.expectSuccessWith
            (Expect.equal
                [ "content/blog/first-post.md"
                , "content/blog/second-post.md"
                ]
            )

-}
expectSuccessWith : (a -> Expectation) -> BackendTaskTest a -> Expectation
expectSuccessWith assertion scriptTest =
    case scriptTest of
        Done { result } ->
            case result of
                Ok value ->
                    assertion value

                Err err ->
                    Expect.fail ("Expected success but the script failed with an error:\n\n" ++ fatalErrorToString err)

        Running state ->
            Expect.fail
                ("Expected the script to complete, but there are still pending requests:\n\n"
                    ++ formatPendingRequests state.pendingRequests
                )

        TestError msg ->
            Expect.fail msg


{-| Assert on the virtual DB state. This is a terminal assertion that also checks
the script completed successfully. Pass the generated `Pages.Db.testConfig` and
an assertion function that receives the decoded DB value.

    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    myDbScript
        |> BackendTaskTest.fromBackendTaskWithDb Pages.Db.testConfig
            { counter = 0 }
        |> BackendTaskTest.expectDb Pages.Db.testConfig
            (\db -> Expect.equal 1 db.counter)

-}
expectDb :
    { a | decode : Bytes -> Maybe db }
    -> (db -> Expectation)
    -> BackendTaskTest b
    -> Expectation
expectDb config assertion scriptTest =
    case scriptTest of
        TestError msg ->
            Expect.fail msg

        Running state ->
            Expect.fail
                ("Expected the script to complete, but there are still pending requests:\n\n"
                    ++ formatPendingRequests state.pendingRequests
                )

        Done { result, virtualDB } ->
            case result of
                Err err ->
                    Expect.fail ("expectDb: Expected success but the script failed with an error:\n\n" ++ fatalErrorToString err)

                Ok _ ->
                    case virtualDB.state of
                        Nothing ->
                            Expect.fail "expectDb: No DB state stored. Did your script perform any DB write operations?"

                        Just bytes ->
                            case config.decode bytes of
                                Just db ->
                                    assertion db

                                Nothing ->
                                    Expect.fail "expectDb: Failed to decode the stored DB bytes."


{-| Assert that the `BackendTask` completed with a `FatalError`. Useful for testing
error handling paths, for example when simulating a network error.

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode
    import Test.BackendTask as BackendTaskTest

    BackendTask.Http.getJson
        "https://api.example.com/data"
        (Decode.succeed ())
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpError
            "GET"
            "https://api.example.com/data"
            BackendTaskTest.NetworkError
        |> BackendTaskTest.expectFailure

-}
expectFailure : BackendTaskTest a -> Expectation
expectFailure scriptTest =
    case scriptTest of
        Done { result } ->
            case result of
                Ok _ ->
                    Expect.fail "Expected failure but the script succeeded."

                Err _ ->
                    Expect.pass

        Running state ->
            Expect.fail
                ("Expected the script to complete, but there are still pending requests:\n\n"
                    ++ formatPendingRequests state.pendingRequests
                )

        TestError msg ->
            Expect.fail msg


{-| Like [`expectFailure`](#expectFailure), but also runs an assertion on the
[`FatalError`](FatalError#FatalError). Use this to verify the specific error
your `BackendTask` produces.

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode
    import Test.BackendTask as BackendTaskTest

    BackendTask.Http.getJson
        "https://api.example.com/data"
        (Decode.succeed ())
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpError
            "GET"
            "https://api.example.com/data"
            BackendTaskTest.NetworkError
        |> BackendTaskTest.expectFailureWith
            (\error ->
                error.title
                    |> String.contains "Http"
                    |> Expect.equal True
            )

-}
expectFailureWith : ({ title : String, body : String } -> Expectation) -> BackendTaskTest a -> Expectation
expectFailureWith assertion scriptTest =
    case scriptTest of
        Done { result } ->
            case result of
                Ok _ ->
                    Expect.fail "Expected failure but the script succeeded."

                Err error ->
                    case error of
                        Pages.Internal.FatalError.FatalError details ->
                            assertion details

        Running state ->
            Expect.fail
                ("Expected the script to complete, but there are still pending requests:\n\n"
                    ++ formatPendingRequests state.pendingRequests
                )

        TestError msg ->
            Expect.fail msg


{-| Assert that the test itself produced an error — for example, a `simulateHttpGet` call
that didn't match any pending request. This is useful for testing that your test helpers
produce the error messages you expect.

    import BackendTask
    import Expect
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    BackendTask.succeed ()
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpGet
            "https://example.com"
            (Encode.object [])
        |> BackendTaskTest.expectTestError
            (\msg ->
                msg
                    |> String.contains "already completed"
                    |> Expect.equal True
            )

-}
expectTestError : (String -> Expectation) -> BackendTaskTest a -> Expectation
expectTestError assertion scriptTest =
    case scriptTest of
        TestError msg ->
            assertion msg

        Done _ ->
            Expect.fail "Expected a test error, but the script completed."

        Running _ ->
            Expect.fail "Expected a test error, but the script is still running."
