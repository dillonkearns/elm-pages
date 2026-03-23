module Test.BackendTask.Internal exposing
    ( BackendTaskTest(..), TestSetup(..), Output(..), SimulatedEffect(..), TimeZoneData
    , fromBackendTask, fromBackendTaskWith, fromScript, fromScriptWith
    , init, withFile, withBinaryFile, withDb, withDbSetTo, withStdin, withEnv, withTime, withTimeZone, withTimeZoneByName, withRandomSeed, withWhich
    , simulateHttpGet, simulateHttpPost, simulateHttp, simulateHttpError, simulateCustom, simulateCommand, simulateCustomStream, simulateStreamHttp
    , simulateQuestion, simulateReadKey
    , ensureHttpGet, ensureHttpPost, ensureCustom, ensureCommand, ensureFileWritten
    , ensureStdout, ensureStderr, ensureOutputWith
    , ensureFile, ensureFileExists, ensureNoFile
    , withVirtualEffects, writeFileEffect, removeFileEffect
    , expectSuccess, expectSuccessWith, expectDb, expectFailure, expectFailureWith, expectTestError
    , toResult
    )

{-| Internal implementation for [`Test.BackendTask`](Test-BackendTask) and its sub-modules.

This module exposes the underlying types with their constructors. Most users
should import [`Test.BackendTask`](Test-BackendTask) instead. Import this module
only when you need type annotations or pattern matching on internal types.


## Types

@docs BackendTaskTest, TestSetup, Output, SimulatedEffect, TimeZoneData


## Building

@docs fromBackendTask, fromBackendTaskWith, fromScript, fromScriptWith


## Test Setup

@docs init, withFile, withBinaryFile, withDb, withDbSetTo, withStdin, withEnv, withTime, withTimeZone, withTimeZoneByName, withRandomSeed, withWhich


## Simulating Effects

@docs simulateHttpGet, simulateHttpPost, simulateHttp, simulateHttpError, simulateCustom, simulateCommand, simulateCustomStream, simulateStreamHttp

@docs simulateQuestion, simulateReadKey


## Assertions

@docs ensureHttpGet, ensureHttpPost, ensureCustom, ensureCommand, ensureFileWritten

@docs ensureStdout, ensureStderr, ensureOutputWith

@docs ensureFile, ensureFileExists, ensureNoFile


## Virtual Effects

@docs withVirtualEffects, writeFileEffect, removeFileEffect


## Terminal Assertions

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
import Pages.Script exposing (Script)
import Pages.StaticHttp.Request as Request
import Pages.StaticHttpRequest exposing (RawRequest(..), Status(..))
import RequestsAndPending
import Set
import Test.GlobMatch
import Test.Runner
import Time
import Yaml.Decode as Yaml


{-| The state of a `BackendTask` under test. Create one with [`fromBackendTask`](#fromBackendTask),
simulate external effects, and finish with [`expectSuccess`](#expectSuccess) or [`expectFailure`](#expectFailure).

    import BackendTask
    import Test.BackendTask as BackendTaskTest

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
    , timeZone : Maybe TimeZoneData
    , timeZonesByName : Dict String TimeZoneData
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
    , timeZone = Nothing
    , timeZonesByName = Dict.empty
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
    = StdoutEffect String
    | StderrEffect String
    | FileWriteEffect { path : String, body : String }


{-| Represents a single output message on either stdout or stderr, preserving
the interleaved ordering. Used with [`ensureOutputWith`](#ensureOutputWith).
-}
type Output
    = Stdout String
    | Stderr String


{-| An effect on the virtual filesystem that a CustomBackendTask declares via
[`withVirtualEffects`](#withVirtualEffects). Create values with
[`writeFileEffect`](#writeFileEffect) and [`removeFileEffect`](#removeFileEffect).
-}
type SimulatedEffect
    = SimWriteFile { path : String, body : String }
    | SimRemoveFile String


{-| Configuration for the initial state of a test. Create with [`init`](#init),
then configure with [`withFile`](#withFile) and [`withDb`](#withDb).

    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
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
init : TestSetup
init =
    TestSetup
        { virtualFS = emptyVirtualFS
        , virtualDB = emptyVirtualDB
        }


{-| Seed a file into the virtual filesystem before the test starts running.

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Stream.fileRead "config.json"
        |> Stream.read
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\{ body } -> Script.log body)
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withFile "config.json" """{"key":"value"}"""
            )
        |> BackendTaskTest.ensureStdout [ """{"key":"value"}""" ]
        |> BackendTaskTest.expectSuccess

-}
withFile : String -> String -> TestSetup -> TestSetup
withFile path content (TestSetup setup) =
    TestSetup { setup | virtualFS = insertFile (normalizePath path) content setup.virtualFS }


{-| Seed a binary file into the virtual filesystem before the test starts running.
Use this for testing `BackendTask.File.binaryFile`.

    import BackendTask
    import BackendTask.File
    import Bytes
    import Bytes.Encode
    import Pages.Script as Script
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
            (BackendTaskTest.init
                |> BackendTaskTest.withBinaryFile "data.bin" testBytes
            )
        |> BackendTaskTest.ensureStdout [ "1" ]
        |> BackendTaskTest.expectSuccess

-}
withBinaryFile : String -> Bytes -> TestSetup -> TestSetup
withBinaryFile path content (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | binaryFiles = Dict.insert (normalizePath path) content vfs.binaryFiles } }


{-| Seed the virtual DB with the default seed value from the generated `testConfig`.
This is the value produced by running the full migration chain from `V1.seed ()`.

Use [`withDbSetTo`](#withDbSetTo) instead when you need a specific initial value.

    import BackendTask exposing (BackendTask)
    import Expect
    import FatalError exposing (FatalError)
    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    incrementCounter : BackendTask FatalError ()
    incrementCounter =
        Pages.Db.update Pages.Db.default (\db -> { db | counter = db.counter + 1 })

    incrementCounter
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withDb Pages.Db.testConfig
            )
        |> BackendTaskTest.expectDb Pages.Db.testConfig
            (\db -> Expect.equal 1 db.counter)

-}
withDb :
    { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes, seed : db }
    -> TestSetup
    -> TestSetup
withDb config =
    withDbSetTo config.seed config


{-| Seed the virtual DB with a specific initial value before the test starts running.

    import BackendTask exposing (BackendTask)
    import Expect
    import FatalError exposing (FatalError)
    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    incrementCounter : BackendTask FatalError ()
    incrementCounter =
        Pages.Db.update Pages.Db.default (\db -> { db | counter = db.counter + 1 })

    incrementCounter
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withDbSetTo { counter = 0 } Pages.Db.testConfig
            )
        |> BackendTaskTest.expectDb Pages.Db.testConfig
            (\db -> Expect.equal 1 db.counter)

-}
withDbSetTo :
    db
    -> { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes }
    -> TestSetup
    -> TestSetup
withDbSetTo initialValue config (TestSetup setup) =
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

    import BackendTask
    import BackendTask.Stream as Stream
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Stream.stdin
        |> Stream.read
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\{ body } -> Script.log body)
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withStdin "hello from stdin"
            )
        |> BackendTaskTest.ensureStdout [ "hello from stdin" ]
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

    import BackendTask
    import BackendTask.Env
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    BackendTask.Env.expect "API_KEY"
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\key -> Script.log key)
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withEnv "API_KEY" "secret123"
            )
        |> BackendTaskTest.ensureStdout [ "secret123" ]
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

    import BackendTask
    import BackendTask.Time
    import Pages.Script as Script
    import Time
    import Test.BackendTask as BackendTaskTest

    BackendTask.Time.now
        |> BackendTask.andThen
            (\time -> Script.log (String.fromInt (Time.posixToMillis time)))
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withTime (Time.millisToPosix 1709827200000)
            )
        |> BackendTaskTest.ensureStdout [ "1709827200000" ]
        |> BackendTaskTest.expectSuccess

-}
withTime : Time.Posix -> TestSetup -> TestSetup
withTime time (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | time = Just time } }


{-| Internal representation of a time zone. Use [`Test.BackendTask.Time.TimeZone`](Test-BackendTask-Time#TimeZone)
for the public API, or [`Test.BackendTask.TimeZone`](Test-BackendTask#TimeZone).
-}
type alias TimeZoneData =
    { defaultOffset : Int, eras : List { start : Int, offset : Int } }


{-| Set the default virtual time zone for `BackendTask.Time.zone`.
-}
withTimeZone : TimeZoneData -> TestSetup -> TestSetup
withTimeZone tz (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | timeZone = Just tz } }


{-| Register a named time zone for `BackendTask.Time.zoneByName`.
-}
withTimeZoneByName : String -> TimeZoneData -> TestSetup -> TestSetup
withTimeZoneByName name tz (TestSetup setup) =
    let
        vfs =
            setup.virtualFS
    in
    TestSetup { setup | virtualFS = { vfs | timeZonesByName = Dict.insert name tz vfs.timeZonesByName } }


{-| Set a fixed random seed for `BackendTask.Random.int32` and `BackendTask.Random.generate`.
Without this, any use of `BackendTask.Random` will produce a test error with a helpful message.

The seed value is returned directly by `BackendTask.Random.int32`. For `BackendTask.Random.generate`,
the seed is used with `Random.initialSeed` to run the generator deterministically.

    import BackendTask
    import BackendTask.Random
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    BackendTask.Random.int32
        |> BackendTask.andThen (\seed -> Script.log (String.fromInt seed))
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withRandomSeed 42
            )
        |> BackendTaskTest.ensureStdout [ "42" ]
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

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.expectWhich "node"
        |> BackendTask.andThen Script.log
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withWhich "node" "/usr/bin/node"
            )
        |> BackendTaskTest.ensureStdout [ "/usr/bin/node" ]
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
and `Script.writeFile` are automatically resolved. You only need to simulate external
effects like HTTP requests and `BackendTask.Custom.run` calls.

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    -- Script.log is auto-resolved, no simulation needed
    Script.log "Hello!"
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

-}
fromBackendTask : BackendTask FatalError a -> BackendTaskTest a
fromBackendTask =
    fromBackendTaskWith init


{-| Start a test with a configured [`TestSetup`](#TestSetup). Use this when you need
to seed initial files or DB state.

    import BackendTask
    import BackendTask.File
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    BackendTask.File.rawFile "config.json"
        |> BackendTask.allowFatal
        |> BackendTask.andThen (\content -> Script.log content)
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withFile "config.json" """{"key":"value"}"""
            )
        |> BackendTaskTest.ensureStdout [ """{"key":"value"}""" ]
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
        , drainedOutputCount = 0
        , virtualFS = setup.virtualFS
        , virtualDB = setup.virtualDB
        , simulatedEffects = Nothing
        }


{-| Start a test from a [`Script`](Pages-Script#Script) value with simulated CLI arguments.
This lets you test the full script including CLI option parsing.

    import Cli.Option as Option
    import Cli.OptionsParser as OptionsParser
    import Cli.Program as Program
    import Pages.Script as Script exposing (Script)
    import Test.BackendTask as BackendTaskTest

    helloScript : Script
    helloScript =
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

    helloScript
        |> BackendTaskTest.fromScript [ "--name", "Dillon" ]
        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
        |> BackendTaskTest.expectSuccess

If the CLI arguments don't match the expected options, you get a `TestError`
with the CLI parser's error message.

-}
fromScript : List String -> Script -> BackendTaskTest ()
fromScript =
    fromScriptWith init


{-| Like [`fromScript`](#fromScript) but with a configured [`TestSetup`](#TestSetup).

    import BackendTask
    import BackendTask.File
    import Pages.Script as Script exposing (Script)
    import Test.BackendTask as BackendTaskTest

    myScript : Script
    myScript =
        Script.withoutCliOptions
            (BackendTask.File.rawFile "config.json"
                |> BackendTask.allowFatal
                |> BackendTask.andThen Script.log
            )

    myScript
        |> BackendTaskTest.fromScriptWith
            (BackendTaskTest.init
                |> BackendTaskTest.withFile "config.json" "{}"
            )
            []
        |> BackendTaskTest.expectSuccess

-}
fromScriptWith : TestSetup -> List String -> Script -> BackendTaskTest ()
fromScriptWith setup cliArgs (Pages.Internal.Script.Script { toConfig }) =
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
    , drainedOutputCount : Int
    , virtualFS : VirtualFS
    , virtualDB : VirtualDB
    , simulatedEffects : Maybe (String -> Encode.Value -> List SimulatedEffect)
    }


type alias DoneState a =
    { result : Result FatalError a
    , trackedEffects : List TrackedEffect
    , drainedOutputCount : Int
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
                    , drainedOutputCount = state.drainedOutputCount
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
                        ("Your script uses Pages.Db, but the test was created without DB support.\n\n"
                            ++ "Use withDb in your TestSetup:\n\n"
                            ++ "    myScript\n"
                            ++ "        |> BackendTaskTest.fromBackendTaskWith\n"
                            ++ "            (BackendTaskTest.init\n"
                            ++ "                |> BackendTaskTest.withDb Pages.Db.testConfig\n"
                            ++ "            )"
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
                                    , drainedOutputCount = state.drainedOutputCount
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
                                    , drainedOutputCount = state.drainedOutputCount
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
    , args : List String
    , portName : Maybe String
    , url : Maybe String
    }


streamPipelineDecoder : Decode.Decoder StreamPipeline
streamPipelineDecoder =
    Decode.map2 StreamPipeline
        (Decode.field "kind" Decode.string)
        (Decode.field "parts"
            (Decode.list streamPartDecoder)
        )


streamPartDecoder : Decode.Decoder StreamPartInfo
streamPartDecoder =
    Decode.map6
        (\name path string command portName url ->
            { name = name
            , path = path
            , string = string
            , command = command
            , args = []
            , portName = portName
            , url = url
            }
        )
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "path" Decode.string))
        (Decode.maybe (Decode.field "string" Decode.string))
        (Decode.maybe (Decode.field "command" Decode.string))
        (Decode.maybe (Decode.field "portName" Decode.string))
        (Decode.maybe (Decode.field "url" Decode.string))
        |> Decode.andThen
            (\part ->
                Decode.oneOf
                    [ Decode.field "args" (Decode.list Decode.string)
                        |> Decode.map (\args -> { part | args = args })
                    , Decode.succeed part
                    ]
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
                                    entry : ( String, Encode.Value )
                                    entry =
                                        jsonAutoResolveEntry hash responseBody

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
                            case parseFrontmatter filePath content of
                                Ok { frontmatterValue, bodyWithoutFrontmatter } ->
                                    Ok
                                        (Encode.object
                                            [ ( "rawFile", Encode.string content )
                                            , ( "withoutFrontmatter", Encode.string bodyWithoutFrontmatter )
                                            , ( "parsedFrontmatter", frontmatterValue )
                                            ]
                                        )

                                Err errorMsg ->
                                    Err errorMsg

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
                    if vfs.timeZone /= Nothing || not (Dict.isEmpty vfs.timeZonesByName) then
                        -- Auto-resolve with epoch 0 when a timezone is configured
                        -- but no explicit time is set. This avoids requiring withTime
                        -- just because zone/zoneByName internally chains through now.
                        Ok (Encode.int 0)

                    else
                        Err
                            ("BackendTask.Time.now requires a virtual time.\n\n"
                                ++ "Use withTime in your TestSetup:\n\n"
                                ++ "    BackendTaskTest.init\n"
                                ++ "        |> BackendTaskTest.withTime (Time.millisToPosix 1709827200000)"
                            )

        "elm-pages-internal://timezone" ->
            let
                maybeTzId =
                    decodeJsonBody (Decode.field "tzId" Decode.string) req
            in
            case maybeTzId of
                Just tzId ->
                    case Dict.get tzId vfs.timeZonesByName of
                        Just tz ->
                            Ok (encodeTimeZone tz)

                        Nothing ->
                            Err
                                ("BackendTask.Time.zoneByName \""
                                    ++ tzId
                                    ++ "\" requires a virtual timezone.\n\n"
                                    ++ "Use withTimeZoneByName in your TestSetup:\n\n"
                                    ++ "    BackendTaskTest.init\n"
                                    ++ "        |> BackendTaskTime.withTimeZoneByName \""
                                    ++ tzId
                                    ++ "\"\n"
                                    ++ "            (BackendTaskTime.fixedOffsetZone -300)"
                                )

                Nothing ->
                    case vfs.timeZone of
                        Just tz ->
                            Ok (encodeTimeZone tz)

                        Nothing ->
                            Err
                                ("BackendTask.Time.zone requires a virtual timezone.\n\n"
                                    ++ "Use withTimeZone in your TestSetup:\n\n"
                                    ++ "    BackendTaskTest.init\n"
                                    ++ "        |> BackendTaskTime.withTimeZone BackendTaskTime.utc"
                                )

        "elm-pages-internal://randomSeed" ->
            case vfs.randomSeed of
                Just seed ->
                    Ok (Encode.int seed)

                Nothing ->
                    Err
                        ("BackendTask.Random requires a virtual random seed.\n\n"
                            ++ "Use withRandomSeed in your TestSetup:\n\n"
                            ++ "    BackendTaskTest.init\n"
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

                entry : ( String, Encode.Value )
                entry =
                    jsonAutoResolveEntry hash (buildStreamResponseBody pipeline.kind Encode.null simulationResult)
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


buildStreamResponseBody : String -> Encode.Value -> StreamSimResult -> Encode.Value
buildStreamResponseBody kind metadata simResult =
    case simResult.error of
        Just errorMsg ->
            Encode.object [ ( "error", Encode.string errorMsg ) ]

        Nothing ->
            case kind of
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
                            [ StdoutEffect message ]

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
            case decodeFromToPaths req of
                Just ( from, to ) ->
                    case getAnyFile from vfs of
                        Just (TextFile content) ->
                            Ok { vfs | files = Dict.insert to content vfs.files }

                        Just (BinaryFile content) ->
                            Ok { vfs | binaryFiles = Dict.insert to content vfs.binaryFiles }

                        Nothing ->
                            Err ("Script.copyFile failed: source file \"" ++ from ++ "\" not found in virtual filesystem.")

                Nothing ->
                    Ok vfs

        "elm-pages-internal://move" ->
            case decodeFromToPaths req of
                Just ( from, to ) ->
                    if from == to then
                        Ok vfs

                    else
                        case getAnyFile from vfs of
                            Just (TextFile content) ->
                                Ok { vfs | files = Dict.insert to content vfs.files |> Dict.remove from }

                            Just (BinaryFile content) ->
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


parseFrontmatter : String -> String -> Result String { frontmatterValue : Encode.Value, bodyWithoutFrontmatter : String }
parseFrontmatter filePath content =
    let
        -- Normalize Windows line endings before parsing
        normalized =
            String.replace "\u{000D}\n" "\n" content
    in
    if String.startsWith "---\n" normalized then
        case String.indexes "\n---\n" (String.dropLeft 3 normalized) of
            firstEnd :: _ ->
                let
                    frontmatterString =
                        String.slice 4 (firstEnd + 3) normalized

                    bodyAfterMarker =
                        String.dropLeft (firstEnd + 3 + 5) normalized
                in
                case Decode.decodeString Decode.value frontmatterString of
                    Ok jsonValue ->
                        Ok
                            { frontmatterValue = jsonValue
                            , bodyWithoutFrontmatter = bodyAfterMarker
                            }

                    Err _ ->
                        case Yaml.fromString yamlToJsonValueDecoder frontmatterString of
                            Ok jsonValue2 ->
                                Ok
                                    { frontmatterValue = jsonValue2
                                    , bodyWithoutFrontmatter = bodyAfterMarker
                                    }

                            Err yamlError ->
                                Err
                                    ("File \""
                                        ++ filePath
                                        ++ "\" has frontmatter (between --- markers), but it could not be parsed as JSON or YAML.\n\n"
                                        ++ "YAML error: "
                                        ++ Yaml.errorToString yamlError
                                    )

            [] ->
                Ok
                    { frontmatterValue = Encode.null
                    , bodyWithoutFrontmatter = normalized
                    }

    else
        Ok
            { frontmatterValue = Encode.null
            , bodyWithoutFrontmatter = normalized
            }


yamlToJsonValueDecoder : Yaml.Decoder Encode.Value
yamlToJsonValueDecoder =
    Yaml.oneOf
        [ Yaml.map (\_ -> Encode.null) Yaml.null
        , Yaml.map Encode.bool Yaml.bool
        , Yaml.map Encode.int Yaml.int
        , Yaml.map Encode.float Yaml.float
        , Yaml.map Encode.string Yaml.string
        , Yaml.map (Encode.list identity) (Yaml.list (Yaml.lazy (\() -> yamlToJsonValueDecoder)))
        , Yaml.map
            (\d ->
                d
                    |> Dict.toList
                    |> Encode.object
            )
            (Yaml.dict (Yaml.lazy (\() -> yamlToJsonValueDecoder)))
        ]


resolveFilePath : Request.Request -> String -> String
resolveFilePath req path =
    let
        combined =
            case req.dir of
                [] ->
                    path

                dirs ->
                    if String.startsWith "/" path then
                        path

                    else
                        String.join "/" dirs ++ "/" ++ path
    in
    normalizePath combined


normalizePath : String -> String
normalizePath path =
    let
        isAbsolute =
            String.startsWith "/" path

        segments =
            path
                |> String.split "/"
                |> List.filter (\s -> s /= "" && s /= ".")

        normalized =
            List.foldl
                (\segment accum ->
                    if segment == ".." then
                        case accum of
                            [] ->
                                []

                            _ :: rest ->
                                rest

                    else
                        segment :: accum
                )
                []
                segments
                |> List.reverse
    in
    if isAbsolute then
        "/" ++ String.join "/" normalized

    else
        String.join "/" normalized


type VirtualFile
    = TextFile String
    | BinaryFile Bytes


getAnyFile : String -> VirtualFS -> Maybe VirtualFile
getAnyFile path vfs =
    case Dict.get path vfs.files of
        Just content ->
            Just (TextFile content)

        Nothing ->
            Dict.get path vfs.binaryFiles
                |> Maybe.map BinaryFile


decodeFromToPaths : Request.Request -> Maybe ( String, String )
decodeFromToPaths req =
    case decodeJsonBody (Decode.map2 Tuple.pair (Decode.field "from" Decode.string) (Decode.field "to" Decode.string)) req of
        Just ( rawFrom, rawTo ) ->
            Just ( resolveFilePath req rawFrom, resolveFilePath req rawTo )

        Nothing ->
            Nothing


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
                    bytesAutoResolveEntry hash
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
                    bytesAutoResolveEntry hash
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


encodeTimeZone : TimeZoneData -> Encode.Value
encodeTimeZone { defaultOffset, eras } =
    Encode.object
        [ ( "defaultOffset", Encode.int defaultOffset )
        , ( "eras"
          , Encode.list
                (\era ->
                    Encode.object
                        [ ( "start", Encode.int era.start )
                        , ( "offset", Encode.int era.offset )
                        ]
                )
                eras
          )
        ]


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
            dbJsonResponse hash (Encode.string "test-lock-token") accum

        "elm-pages-internal://db-read-meta" ->
            let
                responseBytes =
                    constructDbReadMetaBytes accum.virtualDB
            in
            { accum
                | jsonEntries = bytesAutoResolveEntry hash :: accum.jsonEntries
                , bytesEntries = Dict.insert hash responseBytes accum.bytesEntries
            }

        "elm-pages-internal://db-write" ->
            dbWriteResponse req hash accum

        "elm-pages-internal://db-migrate-write" ->
            dbWriteResponse req hash accum

        _ ->
            dbJsonResponse hash Encode.null accum


dbJsonResponse : String -> Encode.Value -> AutoResolveResult -> AutoResolveResult
dbJsonResponse hash body accum =
    { accum | jsonEntries = jsonAutoResolveEntry hash body :: accum.jsonEntries }


dbWriteResponse : Request.Request -> String -> AutoResolveResult -> AutoResolveResult
dbWriteResponse req hash accum =
    let
        newVirtualDB =
            case extractBytesBody req of
                Just wire3Bytes ->
                    { state = Just wire3Bytes
                    , dbConfig = accum.virtualDB.dbConfig
                    }

                Nothing ->
                    accum.virtualDB
    in
    { accum
        | jsonEntries = jsonAutoResolveEntry hash Encode.null :: accum.jsonEntries
        , virtualDB = newVirtualDB
    }


responseEntry : String -> Encode.Value -> ( String, Encode.Value )
responseEntry hash responseValue =
    ( hash, Encode.object [ ( "response", responseValue ) ] )


jsonAutoResolveEntry : String -> Encode.Value -> ( String, Encode.Value )
jsonAutoResolveEntry hash body =
    responseEntry hash
        (Encode.object
            [ ( "bodyKind", Encode.string "json" )
            , ( "body", body )
            ]
        )


bytesAutoResolveEntry : String -> ( String, Encode.Value )
bytesAutoResolveEntry hash =
    responseEntry hash
        (Encode.object
            [ ( "bodyKind", Encode.string "bytes" ) ]
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


{-| General-purpose HTTP simulation. Supports any HTTP method, any status code,
custom response headers, and a response body. Use this when you need more control
than [`simulateHttpGet`](#simulateHttpGet) or [`simulateHttpPost`](#simulateHttpPost) provide.

    import BackendTask
    import BackendTask.Http
    import FatalError
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    type alias User =
        { name : String }

    userDecoder : Decode.Decoder User
    userDecoder =
        Decode.map (\name -> { name = name })
            (Decode.field "name" Decode.string)

    fallbackUser : User
    fallbackUser =
        { name = "Unknown user" }

    BackendTask.Http.getJson
        "https://api.example.com/users/999"
        userDecoder
        |> BackendTask.onError
            (\err ->
                case err of
                    BackendTask.Http.BadStatus { statusCode } _ ->
                        if statusCode == 404 then
                            BackendTask.succeed fallbackUser
                        else
                            BackendTask.fail (FatalError.fromString "API error")
                    _ ->
                        BackendTask.fail (FatalError.fromString "Network error")
            )
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttp
            { method = "GET", url = "https://api.example.com/users/999" }
            { statusCode = 404
            , statusText = "Not Found"
            , headers = []
            , body = Encode.object [ ( "error", Encode.string "User not found" ) ]
            }
        |> BackendTaskTest.expectSuccess

-}
simulateHttp :
    { method : String, url : String }
    -> { statusCode : Int, statusText : String, headers : List ( String, String ), body : Encode.Value }
    -> BackendTaskTest a
    -> BackendTaskTest a
simulateHttp { method, url } { statusCode, statusText, headers, body } =
    let
        responseValue =
            Encode.object
                [ ( "statusCode", Encode.int statusCode )
                , ( "statusText", Encode.string statusText )
                , ( "headers"
                  , headers
                        |> List.map (\( k, v ) -> ( k, Encode.string v ))
                        |> Encode.object
                  )
                , ( "url", Encode.string url )
                , ( "bodyKind", Encode.string "json" )
                , ( "body", body )
                ]
    in
    simulateHttpResponse "simulateHttp" method url responseValue


{-| Simulate a pending HTTP request failing with an error. The error string
should be `"NetworkError"` or `"Timeout"`.

    simulateHttpError "GET" "https://api.example.com/data" "NetworkError"

-}
simulateHttpError : String -> String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateHttpError method url errorString =
    let
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
resolveSimulation :
    String
    -> String
    -> (List Request.Request -> Maybe ( Request.Request, List Request.Request ))
    -> (Request.Request -> List Request.Request -> RunningState a -> BackendTaskTest a)
    -> BackendTaskTest a
    -> BackendTaskTest a
resolveSimulation callerName description finder onMatch scriptTest =
    case scriptTest of
        Running state ->
            case finder state.pendingRequests of
                Just ( matchedReq, remaining ) ->
                    onMatch matchedReq remaining state

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


advanceOrStay : RunningState a -> BackendTaskTest a
advanceOrStay newState =
    if List.isEmpty newState.pendingRequests then
        advanceWithAutoResolve newState

    else
        Running newState


{-| Simulate a response for a [`BackendTask.Custom.run`](BackendTask-Custom#run) call.

Provide the port name and the JSON response value to resolve the matching pending request.

    import Json.Encode as Encode

    myScript
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCustom "myPort" (Encode.string "hello")
        |> BackendTaskTest.expectSuccess

-}
simulateCustom : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateCustom portName jsonResponse =
    resolveSimulation "simulateCustom"
        ("BackendTask.Custom.run call for port \"" ++ portName ++ "\"")
        (findMatchingPort portName)
        (\matchedReq remaining state ->
            let
                entry =
                    jsonAutoResolveEntry (Request.hash matchedReq) jsonResponse

                requestBody =
                    case matchedReq.body of
                        StaticHttpBody.JsonBody json ->
                            json

                        _ ->
                            Encode.null

                handlerEffects =
                    case state.simulatedEffects of
                        Just handler ->
                            handler portName requestBody

                        Nothing ->
                            []
            in
            advanceOrStay
                { state
                    | responseEntries = entry :: state.responseEntries
                    , pendingRequests = remaining
                    , virtualFS = applySimulatedEffects handlerEffects state.virtualFS
                }
        )


{-| Simulate a pending stream pipeline that contains a `Stream.command`. The framework
handles simulatable parts (`fileRead`, `fileWrite`, `fromString`, `stdin`, `stdout`, `stderr`)
around the command. You only provide the command's output.

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
        (Just commandName)
        scriptTest


commandMetadata : Encode.Value
commandMetadata =
    Encode.object [ ( "exitCode", Encode.int 0 ) ]


{-| Simulate a pending stream pipeline that contains a custom stream part (`Stream.customRead`,
`Stream.customWrite`, or `Stream.customDuplex`). Works like `simulateCommand`. The framework
handles simulatable parts around the CustomBackendTask. You only provide its output.

    import BackendTask.Stream as Stream
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

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
        Nothing
        scriptTest


{-| Simulate a pending stream pipeline that contains an HTTP stream part (`Stream.http` or
`Stream.httpWithInput`). Works like `simulateCommand`. The framework handles simulatable parts
around the HTTP request. You only provide the response body.

    import BackendTask.Stream as Stream
    import Test.BackendTask as BackendTaskTest

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
        Nothing
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

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.question "What is your name? "
        |> BackendTask.andThen
            (\name -> Script.log ("Hello, " ++ name ++ "!"))
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateQuestion "What is your name? " "Dillon"
        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
        |> BackendTaskTest.expectSuccess

-}
simulateQuestion : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateQuestion prompt answer scriptTest =
    simulateInteractive "simulateQuestion" "question" (matchByPrompt prompt) ("question \"" ++ prompt ++ "\"") answer scriptTest


{-| Simulate a pending `Script.readKey` call resolving with the given key.

    import BackendTask
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
        |> BackendTaskTest.ensureStdout [ "confirmed" ]
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
simulateInteractive callerName urlSuffix predicate description answer =
    resolveSimulation callerName
        description
        (findMatchingInteractive ("elm-pages-internal://" ++ urlSuffix) predicate)
        (\matchedReq remaining state ->
            advanceOrStay
                { state
                    | responseEntries = jsonAutoResolveEntry (Request.hash matchedReq) (Encode.string answer) :: state.responseEntries
                    , pendingRequests = remaining
                }
        )


findMatchingInteractive : String -> (Request.Request -> Bool) -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingInteractive targetUrl predicate =
    findMatchingBy (\req -> req.url == targetUrl && predicate req)


{-| Internal helper. Shared implementation for simulateCommand, simulateCustomStream, simulateStreamHttp.
The `maybeEffectsName` parameter, when `Just name`, triggers the `simulatedEffects` handler
with that name (used by `simulateCommand` so that `withVirtualEffects` fires for commands).
-}
simulateStreamByPartName : String -> (StreamPartInfo -> Bool) -> String -> Encode.Value -> String -> Maybe String -> BackendTaskTest a -> BackendTaskTest a
simulateStreamByPartName callerName predicate description metadata opaqueOutput maybeEffectsName =
    resolveSimulation callerName
        ("stream with " ++ description)
        (findMatchingStreamByPart predicate)
        (\matchedReq remaining state ->
            case decodeJsonBody streamPipelineDecoder matchedReq of
                Just pipeline ->
                    let
                        simResult =
                            simulateStreamWithOpaquePart predicate
                                state.virtualFS
                                opaqueOutput
                                (resolveStreamPaths matchedReq pipeline.parts)

                        responseBody =
                            buildStreamResponseBody pipeline.kind metadata simResult

                        matchedPart =
                            List.filter predicate pipeline.parts
                                |> List.head

                        effectsBody =
                            case matchedPart of
                                Just part ->
                                    Encode.list Encode.string part.args

                                Nothing ->
                                    Encode.null

                        handlerEffects =
                            case maybeEffectsName of
                                Just effectsName ->
                                    case state.simulatedEffects of
                                        Just handler ->
                                            handler effectsName effectsBody

                                        Nothing ->
                                            []

                                Nothing ->
                                    []
                    in
                    advanceOrStay
                        { state
                            | responseEntries = jsonAutoResolveEntry (Request.hash matchedReq) responseBody :: state.responseEntries
                            , pendingRequests = remaining
                            , virtualFS = applySimulatedEffects handlerEffects simResult.virtualFS
                            , trackedEffects = state.trackedEffects ++ simResult.effects
                        }

                Nothing ->
                    TestError (callerName ++ ": Failed to decode stream pipeline.")
        )


findMatchingStreamByPart : (StreamPartInfo -> Bool) -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingStreamByPart predicate =
    findMatchingBy (\req -> req.url == "elm-pages-internal://stream" && streamHasPart predicate req)


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
simulateHttpResponse callerName method url responseValue =
    resolveSimulation callerName
        (method ++ " request for\n\n    " ++ url)
        (findMatchingRequest method url)
        (\matchedReq remaining state ->
            advanceOrStay
                { state
                    | responseEntries = responseEntry (Request.hash matchedReq) (adjustBodyKindForExpect matchedReq responseValue) :: state.responseEntries
                    , pendingRequests = remaining
                }
        )


adjustBodyKindForExpect : Request.Request -> Encode.Value -> Encode.Value
adjustBodyKindForExpect req responseValue =
    let
        expectHeader =
            req.headers
                |> List.filterMap
                    (\( key, value ) ->
                        if key == "elm-pages-internal" then
                            Just value

                        else
                            Nothing
                    )
                |> List.head
                |> Maybe.withDefault ""
    in
    case expectHeader of
        "ExpectWhatever" ->
            -- Replace bodyKind with "whatever" so the Elm decoder produces WhateverBody
            case Decode.decodeValue (Decode.keyValuePairs Decode.value) responseValue of
                Ok pairs ->
                    pairs
                        |> List.map
                            (\( k, v ) ->
                                if k == "bodyKind" then
                                    ( k, Encode.string "whatever" )

                                else
                                    ( k, v )
                            )
                        |> Encode.object

                Err _ ->
                    responseValue

        "ExpectString" ->
            -- Replace bodyKind with "string" and convert body to string if needed
            case Decode.decodeValue (Decode.keyValuePairs Decode.value) responseValue of
                Ok pairs ->
                    pairs
                        |> List.map
                            (\( k, v ) ->
                                if k == "bodyKind" then
                                    ( k, Encode.string "string" )

                                else if k == "body" then
                                    case Decode.decodeValue Decode.string v of
                                        Ok _ ->
                                            ( k, v )

                                        Err _ ->
                                            ( k, Encode.string (Encode.encode 0 v) )

                                else
                                    ( k, v )
                            )
                        |> Encode.object

                Err _ ->
                    responseValue

        _ ->
            responseValue


findMatchingBy : (Request.Request -> Bool) -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingBy predicate requests =
    findMatchingByHelper predicate [] requests


findMatchingByHelper : (Request.Request -> Bool) -> List Request.Request -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingByHelper predicate before after =
    case after of
        [] ->
            Nothing

        req :: rest ->
            if predicate req then
                Just ( req, List.reverse before ++ rest )

            else
                findMatchingByHelper predicate (req :: before) rest


findMatchingRequest : String -> String -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingRequest method url =
    findMatchingBy (\req -> req.method == method && req.url == url)


findMatchingPort : String -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingPort portName =
    findMatchingBy (\req -> req.url == "elm-pages-internal://port" && getPortName req == Just portName)


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


stillRunningError : List Request.Request -> String
stillRunningError pendingRequests =
    "Expected the script to complete, but there are still pending requests:\n\n"
        ++ formatPendingRequests pendingRequests
        ++ "\nHint: Use a simulate function (like simulateHttpGet, simulateCustom, etc.)\n"
        ++ "to provide a response for each pending request before calling the terminal assertion."


{-| Assert that a GET request to the given URL is currently pending, without resolving it.
This is useful for verifying that requests are issued in parallel. If both `ensureHttpGet`
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

Note: you don't need `ensureHttpGet` before every `simulateHttpGet`.
`simulateHttpGet` already fails if the request isn't pending. Use `ensure`
when you want to verify request timing (parallel vs sequential).

-}
ensureHttpGet : String -> BackendTaskTest a -> BackendTaskTest a
ensureHttpGet url =
    ensureHttpRequest "ensureHttpGet" "GET" url


{-| Assert that a POST request to the given URL is currently pending, and run an
assertion on the request body. Does not resolve the request. Use this to verify
request timing (parallel vs sequential) and that the correct data was sent.

    import BackendTask
    import BackendTask.Http
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    BackendTask.Http.post
        "https://api.example.com/items"
        (BackendTask.Http.jsonBody
            (Encode.object [ ( "name", Encode.string "test" ) ])
        )
        (BackendTask.Http.expectJson (Decode.succeed ()))
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
            (\body ->
                case Decode.decodeValue (Decode.field "name" Decode.string) body of
                    Ok name ->
                        Expect.equal "test" name

                    Err err ->
                        Expect.fail (Decode.errorToString err)
            )
        |> BackendTaskTest.simulateHttpPost "https://api.example.com/items" Encode.null
        |> BackendTaskTest.expectSuccess

If you don't need to check the body, just use `Expect.pass`:

    |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
        (\_ -> Expect.pass)

-}
ensureHttpPost : String -> (Encode.Value -> Expect.Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensureHttpPost url bodyAssertion scriptTest =
    case scriptTest of
        TestError _ ->
            scriptTest

        Done _ ->
            TestError
                ("ensureHttpPost: Expected a pending POST request for\n\n    "
                    ++ url
                    ++ "\n\nbut the script has already completed."
                )

        Running state ->
            case findMatchingRequest "POST" url state.pendingRequests of
                Just ( req, _ ) ->
                    let
                        bodyValue =
                            case req.body of
                                StaticHttpBody.JsonBody json ->
                                    json

                                _ ->
                                    Encode.null
                    in
                    case Test.Runner.getFailureReason (bodyAssertion bodyValue) of
                        Nothing ->
                            scriptTest

                        Just failure ->
                            TestError
                                ("ensureHttpPost: POST request body assertion failed for\n\n    "
                                    ++ url
                                    ++ "\n\n"
                                    ++ failure.description
                                )

                Nothing ->
                    TestError
                        ("ensureHttpPost: Expected a pending POST request for\n\n    "
                            ++ url
                            ++ "\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )


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
and run an assertion on the arguments (the JSON value passed to the port). Does not resolve
the request. Use this to verify request timing (parallel vs sequential) and that the
correct arguments were passed.

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
        |> BackendTaskTest.ensureCustom "hashPassword"
            (\args ->
                Decode.decodeValue Decode.string args
                    |> Expect.equal (Ok "secret123")
            )
        |> BackendTaskTest.simulateCustom "hashPassword"
            (Encode.string "hashed_secret123")
        |> BackendTaskTest.expectSuccess

If you don't need to check the arguments, just use `Expect.pass`:

    |> BackendTaskTest.ensureCustom "hashPassword" (\_ -> Expect.pass)

-}
ensureCustom : String -> (Encode.Value -> Expect.Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensureCustom portName bodyAssertion scriptTest =
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
                Just ( req, _ ) ->
                    let
                        inputValue =
                            case req.body of
                                StaticHttpBody.JsonBody json ->
                                    Decode.decodeValue (Decode.field "input" Decode.value) json
                                        |> Result.withDefault Encode.null

                                _ ->
                                    Encode.null
                    in
                    case Test.Runner.getFailureReason (bodyAssertion inputValue) of
                        Nothing ->
                            scriptTest

                        Just failure ->
                            TestError
                                ("ensureCustom: Custom port \""
                                    ++ portName
                                    ++ "\" argument assertion failed\n\n"
                                    ++ failure.description
                                )

                Nothing ->
                    TestError
                        ("ensureCustom: Expected a pending BackendTask.Custom.run call for port \""
                            ++ portName
                            ++ "\"\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )


{-| Assert that a command with the given name is currently pending, and run an
assertion on its arguments. Does not resolve the request.
-}
ensureCommand : String -> (List String -> Expect.Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensureCommand commandName argsAssertion scriptTest =
    let
        predicate : StreamPartInfo -> Bool
        predicate part =
            part.name == "command" && part.command == Just commandName
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Done _ ->
            TestError
                ("ensureCommand: Expected a pending command \""
                    ++ commandName
                    ++ "\"\n\nbut the script has already completed."
                )

        Running state ->
            case findMatchingStreamByPart predicate state.pendingRequests of
                Just ( req, _ ) ->
                    let
                        args : List String
                        args =
                            case decodeJsonBody streamPipelineDecoder req of
                                Just pipeline ->
                                    pipeline.parts
                                        |> List.filter predicate
                                        |> List.head
                                        |> Maybe.map .args
                                        |> Maybe.withDefault []

                                Nothing ->
                                    []
                    in
                    case Test.Runner.getFailureReason (argsAssertion args) of
                        Nothing ->
                            scriptTest

                        Just failure ->
                            TestError
                                ("ensureCommand: Command \""
                                    ++ commandName
                                    ++ "\" args assertion failed\n\n"
                                    ++ failure.description
                                )

                Nothing ->
                    TestError
                        ("ensureCommand: Expected a pending command \""
                            ++ commandName
                            ++ "\"\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
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
ensureFileWritten expected =
    checkTrackedEffects
        (\effects ->
            if List.member (FileWriteEffect expected) effects then
                Nothing

            else
                Just
                    ("ensureFileWritten: Expected a file write to:\n\n    "
                        ++ expected.path
                        ++ "\n\nbut the file writes are:\n\n"
                        ++ formatFileWrites effects
                    )
        )


{-| Assert that exactly these stdout messages were produced since the last successful
`ensureStdout`, `ensureStderr`, or `ensureOutputWith` call (or since the start of the test).
Both `Script.log` and stream-based stdout (`Stream.pipe Stream.stdout`) are tracked as stdout output.

**Important:** This also implicitly asserts that _no stderr_ output was produced in the same
window. If your script produces both stdout and stderr in the same phase, use
[`ensureOutputWith`](#ensureOutputWith) instead to check both streams together.

On success, all output (stdout and stderr) is drained. Subsequent calls only see new messages.
On failure, messages are NOT drained, preserving them for debugging. This follows the same
drain-on-success pattern as elm-program-test's `ensureOutgoingPortValues`.

    import BackendTask
    import Json.Decode as Decode
    import Json.Encode as Encode
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    -- Simple: check a single message
    Script.log "Hello!"
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureStdout [ "Hello!" ]
        |> BackendTaskTest.expectSuccess

    -- Phase-based: drain between simulation steps
    Script.log "fetching"
        |> BackendTask.andThen
            (\() ->
                BackendTask.Http.getJson "https://example.com/api"
                    (Decode.succeed ())
                    |> BackendTask.allowFatal
            )
        |> BackendTask.andThen (\() -> Script.log "done")
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureStdout [ "fetching" ]
        |> BackendTaskTest.simulateHttpGet "https://example.com/api"
            (Encode.object [])
        |> BackendTaskTest.ensureStdout [ "done" ]
        |> BackendTaskTest.expectSuccess

-}
ensureStdout : List String -> BackendTaskTest a -> BackendTaskTest a
ensureStdout =
    ensureSingleStream "ensureStdout" "stderr" isStdout isStderr


{-| Assert that exactly these stderr messages were produced since the last successful
`ensureStdout`, `ensureStderr`, or `ensureOutputWith` call (or since the start of the test).
Only stream-based stderr output (`Stream.pipe Stream.stderr`) is tracked here.

**Important:** This also implicitly asserts that _no stdout_ output was produced in the same
window. If your script produces both stdout and stderr in the same phase, use
[`ensureOutputWith`](#ensureOutputWith) instead to check both streams together.

Follows the same drain-on-success pattern as [`ensureStdout`](#ensureStdout).

    import BackendTask.Stream as Stream
    import Test.BackendTask as BackendTaskTest

    Stream.fromString "warning!"
        |> Stream.pipe Stream.stderr
        |> Stream.run
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureStderr [ "warning!" ]
        |> BackendTaskTest.expectSuccess

-}
ensureStderr : List String -> BackendTaskTest a -> BackendTaskTest a
ensureStderr =
    ensureSingleStream "ensureStderr" "stdout" isStderr isStdout


ensureSingleStream : String -> String -> (Output -> Maybe String) -> (Output -> Maybe String) -> List String -> BackendTaskTest a -> BackendTaskTest a
ensureSingleStream callerName otherStreamName extractExpected extractUnexpected expectedMessages =
    ensureOutputWith
        (\outputs ->
            let
                unexpected =
                    List.filterMap extractUnexpected outputs

                expected =
                    List.filterMap extractExpected outputs
            in
            if not (List.isEmpty unexpected) then
                Expect.fail
                    (callerName
                        ++ " found unexpected "
                        ++ otherStreamName
                        ++ " output:\n\n"
                        ++ formatStringList unexpected
                        ++ "\n\nUse ensureOutputWith to check both stdout and stderr together."
                    )

            else
                Expect.equal expectedMessages expected
        )


isStdout : Output -> Maybe String
isStdout output =
    case output of
        Stdout msg ->
            Just msg

        Stderr _ ->
            Nothing


isStderr : Output -> Maybe String
isStderr output =
    case output of
        Stderr msg ->
            Just msg

        Stdout _ ->
            Nothing


{-| Assert on the interleaved stdout/stderr output since the last drain, preserving
the ordering between stdout and stderr messages. Drains on success, preserves on failure.

    import BackendTask
    import BackendTask.Stream as Stream
    import Expect
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest exposing (Output(..))

    Script.log "step 1"
        |> BackendTask.andThen
            (\() ->
                Stream.fromString "warning!"
                    |> Stream.pipe Stream.stderr
                    |> Stream.run
            )
        |> BackendTask.andThen (\() -> Script.log "step 2")
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureOutputWith
            (\outputs ->
                Expect.equal
                    [ Stdout "step 1"
                    , Stderr "warning!"
                    , Stdout "step 2"
                    ]
                    outputs
            )
        |> BackendTaskTest.expectSuccess

-}
ensureOutputWith : (List Output -> Expect.Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensureOutputWith checkOutputs scriptTest =
    let
        checkAndDrain wrap state =
            let
                all =
                    extractOutputs state.trackedEffects

                new =
                    List.drop state.drainedOutputCount all
            in
            case Test.Runner.getFailureReason (checkOutputs new) of
                Nothing ->
                    wrap { state | drainedOutputCount = List.length all }

                Just failure ->
                    TestError
                        ("ensureOutputWith: Output assertion failed.\n\n"
                            ++ failure.description
                            ++ "\n\nOutput since last drain:\n\n"
                            ++ formatOutputs new
                        )
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Done state ->
            checkAndDrain Done state

        Running state ->
            checkAndDrain Running state


extractOutputs : List TrackedEffect -> List Output
extractOutputs effects =
    List.filterMap
        (\effect ->
            case effect of
                StdoutEffect msg ->
                    Just (Stdout msg)

                StderrEffect msg ->
                    Just (Stderr msg)

                _ ->
                    Nothing
        )
        effects


formatOutputs : List Output -> String
formatOutputs outputs =
    if List.isEmpty outputs then
        "    (none)"

    else
        outputs
            |> List.map
                (\output ->
                    case output of
                        Stdout msg ->
                            "    stdout: \"" ++ msg ++ "\""

                        Stderr msg ->
                            "    stderr: \"" ++ msg ++ "\""
                )
            |> String.join "\n"


formatStringList : List String -> String
formatStringList msgs =
    msgs
        |> List.map (\msg -> "    \"" ++ msg ++ "\"")
        |> String.join "\n"


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


insertFile : String -> String -> VirtualFS -> VirtualFS
insertFile path content vfs =
    { vfs | files = Dict.insert path content vfs.files }


checkVirtualFS : (VirtualFS -> Maybe String) -> BackendTaskTest a -> BackendTaskTest a
checkVirtualFS check scriptTest =
    let
        applyCheck vfs =
            case check vfs of
                Nothing ->
                    scriptTest

                Just errorMsg ->
                    TestError errorMsg
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Running state ->
            applyCheck state.virtualFS

        Done state ->
            applyCheck state.virtualFS


checkTrackedEffects : (List TrackedEffect -> Maybe String) -> BackendTaskTest a -> BackendTaskTest a
checkTrackedEffects check scriptTest =
    let
        applyCheck effects =
            case check effects of
                Nothing ->
                    scriptTest

                Just errorMsg ->
                    TestError errorMsg
    in
    case scriptTest of
        TestError _ ->
            scriptTest

        Running state ->
            applyCheck state.trackedEffects

        Done state ->
            applyCheck state.trackedEffects


{-| Assert that a file exists in the virtual filesystem with the given content.
This checks the current state. All `Script.writeFile` calls that have been auto-resolved
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
ensureFile path expectedContent =
    checkVirtualFS
        (\vfs ->
            case Dict.get path vfs.files of
                Just actualContent ->
                    if actualContent == expectedContent then
                        Nothing

                    else
                        Just
                            ("ensureFile: File \"" ++ path ++ "\" exists but has different content.\n\nExpected:\n\n    " ++ expectedContent ++ "\n\nActual:\n\n    " ++ actualContent)

                Nothing ->
                    Just
                        ("ensureFile: Expected file \"" ++ path ++ "\" to exist but it was not found.\n\nFiles in virtual filesystem:\n\n" ++ formatVirtualFiles vfs)
        )


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
ensureFileExists path =
    checkVirtualFS
        (\vfs ->
            case Dict.get path vfs.files of
                Just _ ->
                    Nothing

                Nothing ->
                    Just
                        ("ensureFileExists: Expected file \"" ++ path ++ "\" to exist but it was not found.\n\nFiles in virtual filesystem:\n\n" ++ formatVirtualFiles vfs)
        )


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
ensureNoFile path =
    checkVirtualFS
        (\vfs ->
            case Dict.get path vfs.files of
                Just _ ->
                    Just ("ensureNoFile: Expected file \"" ++ path ++ "\" to not exist but it was found.")

                Nothing ->
                    Nothing
        )


{-| Declare virtual effects for CustomBackendTask calls. The handler receives the port name
and the request body (as JSON), and returns a list of [`SimulatedEffect`](#SimulatedEffect)s
to apply when the port is resolved via [`simulateCustom`](#simulateCustom).

This is only for `BackendTask.Custom.run`. Today the available virtual effects update the
virtual filesystem, but the concept can grow over time. This does not enable HTTP, time,
or any other global simulation features. Custom ports still pause and require explicit
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
        |> BackendTaskTest.withVirtualEffects
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
withVirtualEffects : (String -> Encode.Value -> List SimulatedEffect) -> BackendTaskTest a -> BackendTaskTest a
withVirtualEffects handler scriptTest =
    case scriptTest of
        Running state ->
            Running { state | simulatedEffects = Just handler }

        _ ->
            scriptTest


{-| Declare that a CustomBackendTask writes a file to the virtual filesystem.

    BackendTaskTest.writeFileEffect "output.txt" "file content"

-}
writeFileEffect : String -> String -> SimulatedEffect
writeFileEffect path body =
    SimWriteFile { path = path, body = body }


{-| Declare that a CustomBackendTask removes a file from the virtual filesystem.

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


{-| Assert that the `BackendTask` completed successfully. This is a terminal assertion.
It produces an `Expectation` for elm-test, so it should be the last step in your pipeline.

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
            Expect.fail (stillRunningError state.pendingRequests)

        TestError msg ->
            Expect.fail msg


{-| Like [`expectSuccess`](#expectSuccess), but also runs an assertion on the
result value. Use this when your `BackendTask` returns a value you want to check
with elm-test assertions.

    import Expect
    import BackendTask
    import BackendTask.Glob as Glob
    import Test.BackendTask as BackendTaskTest

    Glob.fromString "content/blog/*.md"
        |> BackendTask.map List.sort
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
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
            Expect.fail (stillRunningError state.pendingRequests)

        TestError msg ->
            Expect.fail msg


{-| Extract the result from a completed `BackendTaskTest`. Returns `Err` if the
BackendTask has pending requests, encountered a test error, or failed. Used
internally by `Tui.Test` to resolve effects.
-}
toResult : BackendTaskTest a -> Result String a
toResult scriptTest =
    case scriptTest of
        Done { result } ->
            case result of
                Ok value ->
                    Ok value

                Err err ->
                    Err ("BackendTask failed: " ++ fatalErrorToString err)

        Running state ->
            Err (stillRunningError state.pendingRequests)

        TestError msg ->
            Err msg


{-| Assert on the virtual DB state. This is a terminal assertion that also checks
the script completed successfully. Pass the generated `Pages.Db.testConfig` and
an assertion function that receives the decoded DB value.

    import Expect
    import BackendTask exposing (BackendTask)
    import FatalError exposing (FatalError)
    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    incrementCounter : BackendTask FatalError ()
    incrementCounter =
        Pages.Db.update Pages.Db.default (\db -> { db | counter = db.counter + 1 })

    incrementCounter
        |> BackendTaskTest.fromBackendTaskWith
            (BackendTaskTest.init
                |> BackendTaskTest.withDb Pages.Db.testConfig
            )
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
            Expect.fail (stillRunningError state.pendingRequests)

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
            Expect.fail (stillRunningError state.pendingRequests)

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
            Expect.fail (stillRunningError state.pendingRequests)

        TestError msg ->
            Expect.fail msg


{-| Assert that the test itself produced an error. For example, a `simulateHttpGet` call
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
