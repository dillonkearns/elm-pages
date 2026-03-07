module Test.BackendTask exposing
    ( BackendTaskTest, HttpError(..), fromBackendTask, fromBackendTaskWith, fromBackendTaskWithDb, fromScript, fromScriptWith
    , TestSetup, defaultSetup, withFile, withDb, withStdin
    , simulateHttpGet, simulateHttpPost, simulateHttpError, simulateCustom, simulateCommand
    , ensureHttpGet, ensureHttpPost, ensureCustom, ensureLogged, ensureFileWritten, ensureStdout, ensureStderr
    , expectFile, expectFileExists, expectNoFile
    , SimulatedEffect, withSimulatedEffects, writeFileEffect, removeFileEffect
    , expectSuccess, expectDb, expectFailure, expectTestError
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


## Building

@docs BackendTaskTest, HttpError, fromBackendTask, fromBackendTaskWith, fromBackendTaskWithDb, fromScript, fromScriptWith


## Test Setup

Configure the initial state (seeded files, DB) before the test starts running.

@docs TestSetup, defaultSetup, withFile, withDb, withStdin


## Simulating Effects

@docs simulateHttpGet, simulateHttpPost, simulateHttpError, simulateCustom, simulateCommand


## Inline Assertions

These check conditions mid-pipeline without ending the test. They return the same
`BackendTaskTest` so you can keep chaining.

@docs ensureHttpGet, ensureHttpPost, ensureCustom, ensureLogged, ensureFileWritten, ensureStdout, ensureStderr


## Virtual Filesystem

Built-in filesystem operations (`Script.writeFile`, `Script.removeFile`, etc.) are tracked
in a virtual filesystem. Assert on the final state with these functions.

@docs expectFile, expectFileExists, expectNoFile


## Simulated Effects

Declare virtual filesystem side effects for custom ports. When a custom port is resolved
via [`simulateCustom`](#simulateCustom), the registered handler's effects are applied to the
virtual filesystem automatically.

@docs SimulatedEffect, withSimulatedEffects, writeFileEffect, removeFileEffect


## Terminal Assertions

These end the pipeline and produce an `Expectation` for elm-test.

@docs expectSuccess, expectDb, expectFailure, expectTestError

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
import Pages.Internal.Script
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.StaticHttp.Request as Request
import Pages.StaticHttpRequest exposing (RawRequest(..), Status(..))
import RequestsAndPending
import Test.Runner


{-| The state of a `BackendTask` under test. Create one with [`fromBackendTask`](#fromBackendTask),
simulate external effects, and finish with [`expectSuccess`](#expectSuccess) or [`expectFailure`](#expectFailure).

    BackendTask.succeed ()
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

-}
type BackendTaskTest
    = Running
        { continuation : RawRequest FatalError ()
        , responseEntries : List ( String, Encode.Value )
        , responseBytesEntries : Dict String Bytes
        , pendingRequests : List Request.Request
        , trackedEffects : List TrackedEffect
        , virtualFS : VirtualFS
        , virtualDB : VirtualDB
        , simulatedEffects : Maybe (String -> Encode.Value -> List SimulatedEffect)
        }
    | Done
        { result : Result FatalError ()
        , trackedEffects : List TrackedEffect
        , virtualFS : VirtualFS
        , virtualDB : VirtualDB
        }
    | TestError String


type alias VirtualFS =
    { files : Dict String String
    , stdin : Maybe String
    }


emptyVirtualFS : VirtualFS
emptyVirtualFS =
    { files = Dict.empty
    , stdin = Nothing
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
    TestSetup { setup | virtualFS = { files = setup.virtualFS.files, stdin = Just content } }


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
fromBackendTask : BackendTask FatalError () -> BackendTaskTest
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
fromBackendTaskWith : TestSetup -> BackendTask FatalError () -> BackendTaskTest
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
    -> BackendTaskTest
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
fromScript : List String -> Pages.Internal.Script.Script -> BackendTaskTest
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
fromScriptWith : TestSetup -> List String -> Pages.Internal.Script.Script -> BackendTaskTest
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


type alias RunningState =
    { continuation : RawRequest FatalError ()
    , responseEntries : List ( String, Encode.Value )
    , responseBytesEntries : Dict String Bytes
    , pendingRequests : List Request.Request
    , trackedEffects : List TrackedEffect
    , virtualFS : VirtualFS
    , virtualDB : VirtualDB
    , simulatedEffects : Maybe (String -> Encode.Value -> List SimulatedEffect)
    }


advanceWithAutoResolve : RunningState -> BackendTaskTest
advanceWithAutoResolve state =
    advanceWithAutoResolveHelper 1000 state


advanceWithAutoResolveHelper : Int -> RunningState -> BackendTaskTest
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
    }


streamPipelineDecoder : Decode.Decoder StreamPipeline
streamPipelineDecoder =
    Decode.map2 StreamPipeline
        (Decode.field "kind" Decode.string)
        (Decode.field "parts"
            (Decode.list
                (Decode.map4 StreamPartInfo
                    (Decode.field "name" Decode.string)
                    (Decode.maybe (Decode.field "path" Decode.string))
                    (Decode.maybe (Decode.field "string" Decode.string))
                    (Decode.maybe (Decode.field "command" Decode.string))
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

        _ ->
            False


type alias AutoResolveResult =
    { jsonEntries : List ( String, Encode.Value )
    , trackedEffects : List TrackedEffect
    , bytesEntries : Dict String Bytes
    , virtualDB : VirtualDB
    , virtualFS : VirtualFS
    }


buildAutoResponses : VirtualFS -> VirtualDB -> List Request.Request -> AutoResolveResult
buildAutoResponses vfs virtualDB requests =
    List.foldl
        (\req accum ->
            let
                hash : String
                hash =
                    Request.hash req
            in
            if isDbRequest req then
                processDbRequest req hash accum

            else if req.url == "elm-pages-internal://stream" then
                processStreamRequest req hash accum

            else
                let
                    responseBody : Encode.Value
                    responseBody =
                        autoResponseBody accum.virtualFS req

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

                    newVFS : VirtualFS
                    newVFS =
                        applyVirtualFSEffect req accum.virtualFS
                in
                { accum
                    | jsonEntries = entry :: accum.jsonEntries
                    , trackedEffects = accum.trackedEffects ++ newEffects
                    , virtualFS = newVFS
                }
        )
        { jsonEntries = []
        , trackedEffects = []
        , bytesEntries = Dict.empty
        , virtualDB = virtualDB
        , virtualFS = vfs
        }
        requests


autoResponseBody : VirtualFS -> Request.Request -> Encode.Value
autoResponseBody vfs req =
    case req.url of
        "elm-pages-internal://read-file" ->
            case getStringBody req of
                Just filePath ->
                    case Dict.get filePath vfs.files of
                        Just content ->
                            Encode.object
                                [ ( "rawFile", Encode.string content )
                                , ( "withoutFrontmatter", Encode.string content )
                                ]

                        Nothing ->
                            Encode.object
                                [ ( "errorCode", Encode.string "ENOENT" ) ]

                Nothing ->
                    Encode.null

        "elm-pages-internal://file-exists" ->
            case req.body of
                StaticHttpBody.JsonBody json ->
                    case Decode.decodeValue Decode.string json of
                        Ok filePath ->
                            Encode.bool (Dict.member filePath vfs.files)

                        Err _ ->
                            Encode.bool False

                _ ->
                    Encode.bool False

        _ ->
            Encode.null


processStreamRequest : Request.Request -> String -> AutoResolveResult -> AutoResolveResult
processStreamRequest req hash accum =
    case decodeJsonBody streamPipelineDecoder req of
        Just pipeline ->
            let
                simulationResult =
                    simulateStreamPipeline accum.virtualFS pipeline.parts

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
                            [ FileWriteEffect fileWrite ]

                        Err _ ->
                            []

                _ ->
                    []

        _ ->
            []


applyVirtualFSEffect : Request.Request -> VirtualFS -> VirtualFS
applyVirtualFSEffect req vfs =
    case req.url of
        "elm-pages-internal://write-file" ->
            case decodeJsonBody (Decode.map2 (\p b -> ( p, b )) (Decode.field "path" Decode.string) (Decode.field "body" Decode.string)) req of
                Just ( path, body ) ->
                    { vfs | files = Dict.insert path body vfs.files }

                Nothing ->
                    vfs

        "elm-pages-internal://delete-file" ->
            case decodeJsonBody (Decode.field "path" Decode.string) req of
                Just path ->
                    { vfs | files = Dict.remove path vfs.files }

                Nothing ->
                    vfs

        "elm-pages-internal://copy-file" ->
            case decodeJsonBody (Decode.map2 Tuple.pair (Decode.field "from" Decode.string) (Decode.field "to" Decode.string)) req of
                Just ( from, to ) ->
                    case Dict.get from vfs.files of
                        Just content ->
                            { vfs | files = Dict.insert to content vfs.files }

                        Nothing ->
                            vfs

                Nothing ->
                    vfs

        "elm-pages-internal://move" ->
            case decodeJsonBody (Decode.map2 Tuple.pair (Decode.field "from" Decode.string) (Decode.field "to" Decode.string)) req of
                Just ( from, to ) ->
                    case Dict.get from vfs.files of
                        Just content ->
                            { vfs | files = Dict.insert to content vfs.files |> Dict.remove from }

                        Nothing ->
                            vfs

                Nothing ->
                    vfs

        _ ->
            vfs


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
simulateHttpGet : String -> Encode.Value -> BackendTaskTest -> BackendTaskTest
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
simulateHttpPost : String -> Encode.Value -> BackendTaskTest -> BackendTaskTest
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
simulateHttpError : String -> String -> HttpError -> BackendTaskTest -> BackendTaskTest
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
simulateCustom : String -> Encode.Value -> BackendTaskTest -> BackendTaskTest
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

                        newState : RunningState
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
        |> BackendTaskTest.expectFile "errors.txt" "error: something bad\n"
        |> BackendTaskTest.expectSuccess

For `Stream.run` pipelines, the output is used for downstream parts (like `fileWrite`)
but isn't returned to Elm. For `Stream.read`, it becomes the body.

-}
simulateCommand : String -> String -> BackendTaskTest -> BackendTaskTest
simulateCommand commandName commandOutput scriptTest =
    case scriptTest of
        Running state ->
            case findMatchingStream commandName state.pendingRequests of
                Just ( matchedReq, remaining ) ->
                    let
                        hash : String
                        hash =
                            Request.hash matchedReq
                    in
                    case decodeJsonBody streamPipelineDecoder matchedReq of
                        Just pipeline ->
                            let
                                simResult =
                                    simulateStreamWithCommand state.virtualFS commandName commandOutput pipeline.parts

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
                                                        , ( "metadata", Encode.object [ ( "exitCode", Encode.int 0 ) ] )
                                                        ]

                                                "json" ->
                                                    case Decode.decodeString Decode.value simResult.output of
                                                        Ok jsonValue ->
                                                            Encode.object
                                                                [ ( "body", jsonValue )
                                                                , ( "metadata", Encode.object [ ( "exitCode", Encode.int 0 ) ] )
                                                                ]

                                                        Err _ ->
                                                            Encode.object
                                                                [ ( "body", Encode.string simResult.output )
                                                                , ( "metadata", Encode.object [ ( "exitCode", Encode.int 0 ) ] )
                                                                ]

                                                _ ->
                                                    Encode.null

                                entry : ( String, Encode.Value )
                                entry =
                                    jsonAutoResolveEntry hash responseBody

                                newState : RunningState
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
                            TestError "simulateCommand: Failed to decode stream pipeline."

                Nothing ->
                    TestError
                        ("simulateCommand: Expected a pending stream with command \""
                            ++ commandName
                            ++ "\"\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )

        Done _ ->
            TestError "simulateCommand: The script has already completed. No pending requests to simulate."

        TestError _ ->
            scriptTest


findMatchingStream : String -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingStream commandName requests =
    findMatchingStreamHelper commandName [] requests


findMatchingStreamHelper : String -> List Request.Request -> List Request.Request -> Maybe ( Request.Request, List Request.Request )
findMatchingStreamHelper commandName before after =
    case after of
        [] ->
            Nothing

        req :: rest ->
            if req.url == "elm-pages-internal://stream" && streamHasCommand commandName req then
                Just ( req, List.reverse before ++ rest )

            else
                findMatchingStreamHelper commandName (req :: before) rest


streamHasCommand : String -> Request.Request -> Bool
streamHasCommand commandName req =
    case decodeJsonBody (Decode.field "parts" (Decode.list (Decode.map2 Tuple.pair (Decode.field "name" Decode.string) (Decode.maybe (Decode.field "command" Decode.string))))) req of
        Just parts ->
            List.any (\( name, cmd ) -> name == "command" && cmd == Just commandName) parts

        Nothing ->
            False


simulateStreamWithCommand : VirtualFS -> String -> String -> List StreamPartInfo -> StreamSimResult
simulateStreamWithCommand vfs commandName commandOutput parts =
    let
        ( before, afterIncluding ) =
            splitAtCommand commandName parts

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
                        { output = commandOutput
                        , effects = []
                        , virtualFS = beforeResult.virtualFS
                        , error = Nothing
                        }
                        after
            in
            { afterResult
                | effects = beforeResult.effects ++ afterResult.effects
            }


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

                        _ ->
                            accum
        )
        initial
        parts


splitAtCommand : String -> List StreamPartInfo -> ( List StreamPartInfo, List StreamPartInfo )
splitAtCommand commandName parts =
    splitAtCommandHelper commandName [] parts


splitAtCommandHelper : String -> List StreamPartInfo -> List StreamPartInfo -> ( List StreamPartInfo, List StreamPartInfo )
splitAtCommandHelper commandName before after =
    case after of
        [] ->
            ( List.reverse before, [] )

        part :: rest ->
            if part.name == "command" && part.command == Just commandName then
                ( List.reverse before, part :: rest )

            else
                splitAtCommandHelper commandName (part :: before) rest


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


simulateHttpResponse : String -> String -> String -> Encode.Value -> BackendTaskTest -> BackendTaskTest
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
ensureHttpGet : String -> BackendTaskTest -> BackendTaskTest
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
ensureHttpPost : String -> BackendTaskTest -> BackendTaskTest
ensureHttpPost url =
    ensureHttpRequest "ensureHttpPost" "POST" url


ensureHttpRequest : String -> String -> String -> BackendTaskTest -> BackendTaskTest
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
ensureCustom : String -> BackendTaskTest -> BackendTaskTest
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
ensureLogged : String -> BackendTaskTest -> BackendTaskTest
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
ensureFileWritten : { path : String, body : String } -> BackendTaskTest -> BackendTaskTest
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
ensureStdout : String -> BackendTaskTest -> BackendTaskTest
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
ensureStderr : String -> BackendTaskTest -> BackendTaskTest
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
        |> BackendTaskTest.expectFile "output.txt" "hello"
        |> BackendTaskTest.expectSuccess

-}
expectFile : String -> String -> BackendTaskTest -> BackendTaskTest
expectFile path expectedContent scriptTest =
    let
        checkFS : VirtualFS -> BackendTaskTest
        checkFS vfs =
            case Dict.get path vfs.files of
                Just actualContent ->
                    if actualContent == expectedContent then
                        scriptTest

                    else
                        TestError
                            ("expectFile: File \"" ++ path ++ "\" exists but has different content.\n\nExpected:\n\n    " ++ expectedContent ++ "\n\nActual:\n\n    " ++ actualContent)

                Nothing ->
                    TestError
                        ("expectFile: Expected file \"" ++ path ++ "\" to exist but it was not found.\n\nFiles in virtual filesystem:\n\n" ++ formatVirtualFiles vfs)
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
        |> BackendTaskTest.expectFileExists "output.txt"
        |> BackendTaskTest.expectSuccess

-}
expectFileExists : String -> BackendTaskTest -> BackendTaskTest
expectFileExists path scriptTest =
    let
        checkFS : VirtualFS -> BackendTaskTest
        checkFS vfs =
            case Dict.get path vfs.files of
                Just _ ->
                    scriptTest

                Nothing ->
                    TestError
                        ("expectFileExists: Expected file \"" ++ path ++ "\" to exist but it was not found.\n\nFiles in virtual filesystem:\n\n" ++ formatVirtualFiles vfs)
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
        |> BackendTaskTest.expectNoFile "output.txt"
        |> BackendTaskTest.expectSuccess

-}
expectNoFile : String -> BackendTaskTest -> BackendTaskTest
expectNoFile path scriptTest =
    let
        checkFS : VirtualFS -> BackendTaskTest
        checkFS vfs =
            case Dict.get path vfs.files of
                Just _ ->
                    TestError ("expectNoFile: Expected file \"" ++ path ++ "\" to not exist but it was found.")

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
        |> BackendTaskTest.expectFile "report.pdf" "content"
        |> BackendTaskTest.expectSuccess

-}
withSimulatedEffects : (String -> Encode.Value -> List SimulatedEffect) -> BackendTaskTest -> BackendTaskTest
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


{-| Assert that the `BackendTask` completed successfully. This is a terminal assertion —
it produces an `Expectation` for elm-test, so it should be the last step in your pipeline.

    import BackendTask
    import Test.BackendTask as BackendTaskTest

    BackendTask.succeed ()
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

If the `BackendTask` still has pending requests, the test fails with a message listing them.

-}
expectSuccess : BackendTaskTest -> Expectation
expectSuccess scriptTest =
    case scriptTest of
        Done { result } ->
            case result of
                Ok () ->
                    Expect.pass

                Err _ ->
                    Expect.fail "Expected success but the script failed with an error."

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
    -> BackendTaskTest
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
                Err _ ->
                    Expect.fail "expectDb: Expected success but the script failed with an error."

                Ok () ->
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
expectFailure : BackendTaskTest -> Expectation
expectFailure scriptTest =
    case scriptTest of
        Done { result } ->
            case result of
                Ok () ->
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
expectTestError : (String -> Expectation) -> BackendTaskTest -> Expectation
expectTestError assertion scriptTest =
    case scriptTest of
        TestError msg ->
            assertion msg

        Done _ ->
            Expect.fail "Expected a test error, but the script completed."

        Running _ ->
            Expect.fail "Expected a test error, but the script is still running."
