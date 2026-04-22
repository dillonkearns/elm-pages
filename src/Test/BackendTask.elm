module Test.BackendTask exposing
    ( TestSetup
    , fromBackendTask, fromBackendTaskWith
    , fromScript, fromScriptWith
    , init, withFile, withBinaryFile, withStdin, withEnv, withTime, withRequestTime, withRequestHeader, withRequestCookie, Session, session, withSessionValue, withFlashValue, withSessionCookie, withRandomSeed, withWhich
    , withTimeZoneConfig, withTimeZoneByNameConfig
    , withDb, withDbSetTo
    , simulateHttpGet, simulateHttpPost, simulateHttp, simulateHttpError, simulateHttpStream
    , HttpError(..)
    , simulateCommand
    , simulateCustom, simulateCustomStream
    , simulateQuestion, simulateReadKey
    , Output(..), ensureStdout, ensureStderr, ensureOutputWith
    , ensureFile, ensureFileExists, ensureNoFile, ensureFileWritten
    , ensureHttpGet, ensureHttpPost
    , ensureCustom
    , ensureCommand
    , SimulatedEffect, withVirtualEffects, writeFileEffect, removeFileEffect
    , expectSuccess, expectSuccessWith, expectFailure, expectFailureWith, expectTestError
    , expectDb
    )

{-| Write pure tests for your `BackendTask`s and `Script`s that you can run with `elm-test`.
No HTTP calls, no file I/O, or side effects of any kind. Just regular Elm tests.

Common scripting tasks like file operations, logging, and environment variables
are emulated for you. You only need to tell the test how to simulate unpredictable
events in the outside world (like HTTP responses and shell commands), and what starting
state you want for your file system and environment variables. Everything
else will be emulated for you.

You can test a [`BackendTask`](BackendTask) directly using [`fromBackendTask`](#fromBackendTask)
and [`fromBackendTaskWith`](#fromBackendTaskWith). For testing full `Script` values
including CLI option parsing, use [`fromScript`](#fromScript) and [`fromScriptWith`](#fromScriptWith).


## Predictable effects are emulated automatically

No simulation calls needed. Set the initial state with [`withFile`](#withFile)
and assert on the results with [`ensureFile`](#ensureFile).

    import BackendTask exposing (BackendTask)
    import FatalError exposing (FatalError)
    import Json.Decode as Decode
    import Pages.Script as Script
    import Test exposing (test)
    import Test.BackendTask as BackendTaskTest

    generateDotEnv : String -> BackendTask FatalError ()
    generateDotEnv outputPath =
        BackendTask.File.jsonFile configDecoder "config.json"
            |> BackendTask.allowFatal
            |> BackendTask.andThen
                (\config ->
                    Script.writeFile
                        { path = outputPath
                        , body = toDotEnv config
                        }
                        |> BackendTask.allowFatal
                )

    test "generates .env from config" <|
        \() ->
            generateDotEnv ".env"
                |> BackendTaskTest.fromBackendTaskWith
                    (BackendTaskTest.init
                        |> BackendTaskTest.withFile "config.json"
                            """{"host": "localhost", "port": 3000, "debug": true}"""
                    )
                |> BackendTaskTest.ensureFile ".env"
                    "HOST=localhost\nPORT=3000\nDEBUG=true"
                |> BackendTaskTest.expectSuccess

    configDecoder : Decode.Decoder { host : String, port_ : Int, debug : Bool }
    configDecoder =
        Decode.map3 (\h p d -> { host = h, port_ = p, debug = d })
            (Decode.field "host" Decode.string)
            (Decode.field "port" Decode.int)
            (Decode.field "debug" Decode.bool)

    toDotEnv : { host : String, port_ : Int, debug : Bool } -> String
    toDotEnv config =
        [ "HOST=" ++ config.host
        , "PORT=" ++ String.fromInt config.port_
        , "DEBUG=" ++ (if config.debug then "true" else "false")
        ]
            |> String.join "\n"


## See Also

  - [`Test.BackendTask.Time`](Test-BackendTask-Time) - configure virtual time zones
  - [`Test.PagesProgram`](Test-PagesProgram) - end-to-end tests for elm-pages routes. Uses [`TestSetup`](#TestSetup) to seed initial state and reuses the simulators defined here for route-level HTTP and custom port responses.
  - [`Test.Tui`](Test-Tui) - tests for `Tui.program` values. Uses [`TestSetup`](#TestSetup) to seed initial state and the simulators here to resolve `BackendTask` effects that a TUI performs via `Tui.Effect.perform`.


## Automatic Virtual State Emulation

These effects are emulated automatically against virtual state:

**File operations:**

  - `Script.writeFile`, `Script.removeFile`, `Script.copyFile`, `Script.move` (assert with [`ensureFile`](#ensureFile))
  - `BackendTask.File.rawFile`, `BackendTask.File.jsonFile`, `BackendTask.File.exists` ([`withFile`](#withFile) sets initial state)
  - `BackendTask.Glob` (matches against files set with [`withFile`](#withFile))

**Output:**

  - `Script.log` (assert with [`ensureStdout`](#ensureStdout))

**Environment:**

  - `BackendTask.Env.get`, `BackendTask.Env.expect` ([`withEnv`](#withEnv) sets initial state)
  - `BackendTask.Time.now` ([`withTime`](#withTime) sets initial state)
  - `BackendTask.Time.zone`, `BackendTask.Time.zoneFor`, `BackendTask.Time.zoneByName`, `BackendTask.Time.zoneByNameFor` ([`Test.BackendTask.Time.withTimeZone`](Test-BackendTask-Time#withTimeZone) / [`Test.BackendTask.Time.withTimeZoneByName`](Test-BackendTask-Time#withTimeZoneByName) sets initial state)
  - `BackendTask.Random.generate` ([`withRandomSeed`](#withRandomSeed) sets initial state)
  - `Script.which` ([`withWhich`](#withWhich) sets initial state)

**Database:**

  - `Pages.Db.get`, `Pages.Db.update`, `Pages.Db.transaction` ([`withDb`](#withDb) sets initial state, assert with [`expectDb`](#expectDb))

**CLI parsing:**

  - `Script.withCliOptions`, `Script.withoutCliOptions` (parsed from args passed to [`fromScript`](#fromScript))

**Streams:**

  - `Stream.fromString`, `Stream.stdin`, `Stream.stdout`, `Stream.stderr`
  - `Stream.fileRead`, `Stream.fileWrite`, `Stream.gzip`, `Stream.unzip`

Everything else represents outside data and effects (HTTP requests, shell commands, [`BackendTask.Custom`](BackendTask-Custom) calls)
which you must simulate using the functions below.
If your test case encounters one of these which is not simulated, it will fail with a clear message with instructions for how to
simulate it.


## Building

@docs fromBackendTask, fromBackendTaskWith

@docs fromScript, fromScriptWith


## Test Setup

Seed initial state before the test starts running.

@docs TestSetup, init, withFile, withBinaryFile, withStdin, withEnv, withTime, withRequestTime, withRequestHeader, withRequestCookie, Session, session, withSessionValue, withFlashValue, withSessionCookie, withRandomSeed, withWhich

## Companion Module Helpers

Low-level setup helpers used by [`Test.BackendTask.Time`](Test-BackendTask-Time).

@docs withTimeZoneConfig, withTimeZoneByNameConfig

@docs withDb, withDbSetTo


## Simulating HTTP

@docs simulateHttpGet, simulateHttpPost, simulateHttp, simulateHttpError, simulateHttpStream

@docs HttpError


## Simulating Commands

@docs simulateCommand


## Simulating Custom Ports

@docs simulateCustom, simulateCustomStream


## Simulating Interactive Input

@docs simulateQuestion, simulateReadKey


## Assertions

Check conditions mid-pipeline without ending the test. These return the same
`BackendTaskTest` so you can keep chaining.

@docs Output, ensureStdout, ensureStderr, ensureOutputWith

@docs ensureFile, ensureFileExists, ensureNoFile, ensureFileWritten

@docs ensureHttpGet, ensureHttpPost

@docs ensureCustom

@docs ensureCommand


## Virtual Effects

Declare virtual effects for opaque external operations. Today these effects update the
virtual filesystem. When a call is resolved
via [`simulateCustom`](#simulateCustom) or
[`simulateCommand`](#simulateCommand), the registered handler's
effects are applied to the virtual filesystem automatically.

@docs SimulatedEffect, withVirtualEffects, writeFileEffect, removeFileEffect


## Terminal Assertions

Every test must end with exactly one of these to produce an `Expectation`.

@docs expectSuccess, expectSuccessWith, expectFailure, expectFailureWith, expectTestError

@docs expectDb

-}

import BackendTask exposing (BackendTask)
import Bytes exposing (Bytes)
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Json.Encode as Encode
import Pages.Script exposing (Script)
import Test.BackendTask.Internal as Internal exposing (BackendTaskTest, Session)
import Time



-- TYPES


{-| Represents a single output message on either stdout or stderr, preserving
the interleaved ordering. Used with [`ensureOutputWith`](#ensureOutputWith).
-}
type Output
    = Stdout String
    | Stderr String


{-| The type of HTTP error to simulate with [`simulateHttpError`](#simulateHttpError).

    BackendTaskTest.simulateHttpError
        "GET"
        "https://api.example.com/data"
        BackendTaskTest.NetworkError

-}
type HttpError
    = NetworkError
    | Timeout


{-| The virtual environment used to start a backend task test.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withFile "config.json" """{"key":"value"}"""

-}
type alias TestSetup =
    Internal.TestSetup



-- BUILDING


{-| Start a test from a `BackendTask FatalError a`. Predictable effects like `Script.log`
and `Script.writeFile` are resolved automatically. You only need to simulate external
effects like HTTP requests and `BackendTask.Custom.run` calls.

    import BackendTask
    import Pages.Script as Script
    import Test.BackendTask as BackendTaskTest

    Script.log "Hello!"
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

-}
fromBackendTask : BackendTask FatalError a -> BackendTaskTest a
fromBackendTask =
    Internal.fromBackendTask


{-| Start a test with a configured [`TestSetup`](#init).
Use this when you need to seed initial files, environment variables, or other state.

    import BackendTask.File
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
fromBackendTaskWith =
    Internal.fromBackendTaskWith


{-| Start a test from a [`Script`](Pages-Script#Script) with simulated CLI arguments.
This tests the full script including CLI option parsing.

    import Test.BackendTask as BackendTaskTest

    myScript
        |> BackendTaskTest.fromScript [ "--name", "Dillon" ]
        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
        |> BackendTaskTest.expectSuccess

-}
fromScript : List String -> Script -> BackendTaskTest ()
fromScript =
    Internal.fromScript


{-| Like [`fromScript`](#fromScript) but with a configured [`TestSetup`](#init).

    import Test.BackendTask as BackendTaskTest

    myScript
        |> BackendTaskTest.fromScriptWith
            (BackendTaskTest.init
                |> BackendTaskTest.withFile "config.json" "{}"
            )
            []
        |> BackendTaskTest.expectSuccess

-}
fromScriptWith : TestSetup -> List String -> Script -> BackendTaskTest ()
fromScriptWith =
    Internal.fromScriptWith



-- TEST SETUP


{-| An empty test setup with no seeded state.
-}
init : TestSetup
init =
    Internal.init


{-| Seed a file into the virtual filesystem.

    BackendTaskTest.init
        |> BackendTaskTest.withFile "config.json"
            """{"key":"value"}"""

-}
withFile : String -> String -> TestSetup -> TestSetup
withFile =
    Internal.withFile


{-| Seed a binary file into the virtual filesystem.

    import Bytes.Encode

    BackendTaskTest.init
        |> BackendTaskTest.withBinaryFile "data.bin"
            (Bytes.Encode.encode
            (Bytes.Encode.unsignedInt8 42)
            )

-}
withBinaryFile : String -> Bytes -> TestSetup -> TestSetup
withBinaryFile =
    Internal.withBinaryFile


{-| Seed stdin content for stream pipelines that read from `Stream.stdin`.

    BackendTaskTest.init
        |> BackendTaskTest.withStdin "hello from stdin"

-}
withStdin : String -> TestSetup -> TestSetup
withStdin =
    Internal.withStdin


{-| Seed an environment variable for `BackendTask.Env.get` and `BackendTask.Env.expect`.

    BackendTaskTest.init
        |> BackendTaskTest.withEnv "API_KEY" "secret123"

-}
withEnv : String -> String -> TestSetup -> TestSetup
withEnv =
    Internal.withEnv


{-| Set a fixed virtual time for `BackendTask.Time.now`. Without this, any use of
`BackendTask.Time.now` will produce a test error with a helpful message.

    import Time

    BackendTaskTest.init
        |> BackendTaskTest.withTime (Time.millisToPosix 0)

-}
withTime : Time.Posix -> TestSetup -> TestSetup
withTime =
    Internal.withTime


{-| Set a fixed request time for server-rendered route requests in
[`Test.PagesProgram.start`](Test-PagesProgram#start).

    import Time

    BackendTaskTest.init
        |> BackendTaskTest.withRequestTime (Time.millisToPosix 1709827200000)

-}
withRequestTime : Time.Posix -> TestSetup -> TestSetup
withRequestTime =
    Internal.withRequestTime


{-| Seed a request header for server-rendered route requests in
[`Test.PagesProgram.start`](Test-PagesProgram#start).

Header names are normalized to lowercase.

    BackendTaskTest.init
        |> BackendTaskTest.withRequestHeader "accept-language" "en-US"

-}
withRequestHeader : String -> String -> TestSetup -> TestSetup
withRequestHeader =
    Internal.withRequestHeader


{-| Seed a cookie on the initial server-rendered request in
[`Test.PagesProgram.start`](Test-PagesProgram#start).

    BackendTaskTest.init
        |> BackendTaskTest.withRequestCookie "mysession" "signed-cookie"

-}
withRequestCookie : String -> String -> TestSetup -> TestSetup
withRequestCookie =
    Internal.withRequestCookie


{-| A session value, built up with [`withSessionValue`](#withSessionValue)
and [`withFlashValue`](#withFlashValue), then passed to
[`withSessionCookie`](#withSessionCookie) to sign into a request.
-}
type alias Session =
    Internal.Session


{-| An empty [`Session`](#Session) to build on with
[`withSessionValue`](#withSessionValue) and [`withFlashValue`](#withFlashValue),
then hand off to [`withSessionCookie`](#withSessionCookie).

    import Test.BackendTask as BackendTaskTest

    signedInSession =
        BackendTaskTest.session
            |> BackendTaskTest.withSessionValue "sessionId" "abc123"

-}
session : Session
session =
    Internal.session


{-| Add a persistent session value to a [`Session`](#Session).

    import Test.BackendTask as BackendTaskTest

    signedInSession =
        BackendTaskTest.session
            |> BackendTaskTest.withSessionValue "sessionId" "abc123"

-}
withSessionValue : String -> String -> Session -> Session
withSessionValue =
    Internal.withSessionValue


{-| Add a flash session value to a [`Session`](#Session).

Flash values are available on the next request only, matching
[`Server.Session.withFlash`](Server-Session#withFlash).

    import Test.BackendTask as BackendTaskTest

    sessionWithFlash =
        BackendTaskTest.session
            |> BackendTaskTest.withFlashValue "message" "Welcome back!"

-}
withFlashValue : String -> String -> Session -> Session
withFlashValue =
    Internal.withFlashValue


{-| Seed a signed session cookie for the initial request in
[`Test.PagesProgram.start`](Test-PagesProgram#start).

This keeps the cookie format internal to the test framework, so your tests
work with session values instead of raw signed cookie strings.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withSessionCookie
            { name = "mysession"
            , session =
                BackendTaskTest.session
                    |> BackendTaskTest.withSessionValue "sessionId" "abc123"
                    |> BackendTaskTest.withFlashValue "message" "Welcome back!"
            }

-}
withSessionCookie : { name : String, session : Session } -> TestSetup -> TestSetup
withSessionCookie =
    Internal.withSessionCookie


{-| Set a fixed random seed for `BackendTask.Random.int32` and `BackendTask.Random.generate`.
Without this, any use of `BackendTask.Random` will produce a test error with a helpful message.

    BackendTaskTest.init
        |> BackendTaskTest.withRandomSeed 42

-}
withRandomSeed : Int -> TestSetup -> TestSetup
withRandomSeed =
    Internal.withRandomSeed


{-| Register a command as available for `Script.which` and `Script.expectWhich`.
Commands not registered will return `Nothing` from `Script.which`.

    BackendTaskTest.init
        |> BackendTaskTest.withWhich "node" "/usr/bin/node"

-}
withWhich : String -> String -> TestSetup -> TestSetup
withWhich =
    Internal.withWhich


{-| Low-level helper used by [`Test.BackendTask.Time.withTimeZone`](Test-BackendTask-Time#withTimeZone).

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withTimeZoneConfig
            { defaultOffset = 0, eras = [] }

-}
withTimeZoneConfig :
    { defaultOffset : Int, eras : List { start : Int, offset : Int } }
    -> TestSetup
    -> TestSetup
withTimeZoneConfig =
    Internal.withTimeZone


{-| Low-level helper used by [`Test.BackendTask.Time.withTimeZoneByName`](Test-BackendTask-Time#withTimeZoneByName).

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withTimeZoneByNameConfig "America/Chicago"
            { defaultOffset = -360, eras = [] }

-}
withTimeZoneByNameConfig :
    String
    -> { defaultOffset : Int, eras : List { start : Int, offset : Int } }
    -> TestSetup
    -> TestSetup
withTimeZoneByNameConfig =
    Internal.withTimeZoneByName


{-| Seed the virtual DB with the default seed value from the generated `testConfig`.

The [elm-pages Script DB](https://elm-pages.com/docs/elm-pages-scripts-db/) is a
pure Elm type that is serialized to disk. Since it's just a plain Elm value, the
test framework can realistically simulate it. Reads, writes, and updates all
work against an in-memory copy. The only difference from production is that
instead of reading the initial value from a binary file of the serialized Elm
type on disk, you provide it directly with this function or [`withDbSetTo`](#withDbSetTo).

    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withDb Pages.Db.testConfig

-}
withDb :
    { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes, seed : db }
    -> TestSetup
    -> TestSetup
withDb =
    Internal.withDb


{-| Seed the virtual DB with a specific initial value.

    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withDbSetTo { counter = 5 } Pages.Db.testConfig

-}
withDbSetTo :
    db
    -> { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes }
    -> TestSetup
    -> TestSetup
withDbSetTo =
    Internal.withDbSetTo



-- SIMULATING HTTP


{-| Simulate a pending HTTP GET request resolving with the given JSON response body.

    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpGet
            "https://api.example.com/data"
            (Encode.object [ ( "key", Encode.string "value" ) ])
        |> BackendTaskTest.expectSuccess

-}
simulateHttpGet : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateHttpGet url jsonResponse =
    Internal.simulateHttpGet url jsonResponse


{-| Simulate a pending HTTP POST request resolving with the given JSON response body.

    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpPost
            "https://api.example.com/items"
            (Encode.object [ ( "id", Encode.int 42 ) ])
        |> BackendTaskTest.expectSuccess

-}
simulateHttpPost : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateHttpPost url jsonResponse =
    Internal.simulateHttpPost url jsonResponse


{-| Simulate any HTTP request with full control over method, status code, headers, and body.

    import Test.BackendTask as BackendTaskTest
    import Json.Encode as Encode

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttp
            { method = "PUT", url = "https://api.example.com/item/1" }
            { statusCode = 204
            , statusText = "No Content"
            , headers = []
            , body = Encode.null
            }
        |> BackendTaskTest.expectSuccess

-}
simulateHttp :
    { method : String, url : String }
    -> { statusCode : Int, statusText : String, headers : List ( String, String ), body : Encode.Value }
    -> BackendTaskTest a
    -> BackendTaskTest a
simulateHttp request response =
    Internal.simulateHttp request response


{-| Simulate a pending HTTP request failing with an [`HttpError`](#HttpError).

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpError "GET" "https://api.example.com/data" BackendTaskTest.NetworkError
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
    in
    Internal.simulateHttpError method url errorString



-- SIMULATING COMMANDS


{-| Simulate a pending `Stream.command` / `Script.command` / `Script.exec` call.
The framework handles simulatable parts around the command. You provide the
command name and its output.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCommand "grep" "matched line\n"
        |> BackendTaskTest.expectSuccess

-}
simulateCommand : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateCommand commandName commandOutput =
    Internal.simulateCommand commandName commandOutput



-- SIMULATING CUSTOM PORTS


{-| Simulate a pending `BackendTask.Custom.run` call resolving with the given JSON value.
The port name must exactly match the first argument passed to `BackendTask.Custom.run`.

    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCustom "hashPassword" (Encode.string "hashed_secret123")
        |> BackendTaskTest.expectSuccess

-}
simulateCustom : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateCustom portName jsonResponse =
    Internal.simulateCustom portName jsonResponse



-- SIMULATING STREAMS


{-| Simulate a pending stream pipeline containing a custom stream part
(`Stream.customRead`, `Stream.customWrite`, or `Stream.customDuplex`).
The framework handles simulatable parts around the custom part. You only
provide its output.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCustomStream "myTransform" "transformed output"
        |> BackendTaskTest.expectSuccess

-}
simulateCustomStream : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateCustomStream portName portOutput =
    Internal.simulateCustomStream portName portOutput


{-| Simulate a pending stream pipeline containing an HTTP stream part
(`Stream.http` or `Stream.httpWithInput`). The framework handles simulatable
parts around the HTTP request. You only provide the response body.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpStream "https://api.example.com" "response body"
        |> BackendTaskTest.expectSuccess

-}
simulateHttpStream : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateHttpStream url httpOutput =
    Internal.simulateStreamHttp url httpOutput



-- SIMULATING INTERACTIVE INPUT


{-| Simulate a pending `Script.question` call. The prompt must match the prompt
text passed to `Script.question`.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateQuestion "What is your name? " "Dillon"
        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
        |> BackendTaskTest.expectSuccess

-}
simulateQuestion : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateQuestion prompt answer =
    Internal.simulateQuestion prompt answer


{-| Simulate a pending `Script.readKey` call resolving with the given key.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateReadKey "y"
        |> BackendTaskTest.ensureStdout [ "confirmed" ]
        |> BackendTaskTest.expectSuccess

-}
simulateReadKey : String -> BackendTaskTest a -> BackendTaskTest a
simulateReadKey key =
    Internal.simulateReadKey key



-- OUTPUT ASSERTIONS


{-| Assert that exactly these stdout messages were produced since the last drain.
Fails if any stderr output is present. Use [`ensureOutputWith`](#ensureOutputWith)
to check both stdout and stderr together.

    Script.log "Hello!"
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureStdout [ "Hello!" ]
        |> BackendTaskTest.expectSuccess

-}
ensureStdout : List String -> BackendTaskTest a -> BackendTaskTest a
ensureStdout expectedMessages =
    ensureOutputWith
        (\outputs ->
            let
                unexpected =
                    List.filterMap isStderrOutput outputs

                expected =
                    List.filterMap isStdoutOutput outputs
            in
            if not (List.isEmpty unexpected) then
                Expect.fail
                    ("ensureStdout found unexpected stderr output:\n\n"
                        ++ formatStringList unexpected
                        ++ "\n\nUse ensureOutputWith to check both stdout and stderr together."
                    )

            else
                Expect.equal expectedMessages expected
        )


{-| Assert that exactly these stderr messages were produced since the last drain.
Fails if any stdout output is present. Use [`ensureOutputWith`](#ensureOutputWith)
to check both stdout and stderr together.

    Stream.fromString "warning!"
        |> Stream.pipe Stream.stderr
        |> Stream.run
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureStderr [ "warning!" ]
        |> BackendTaskTest.expectSuccess

-}
ensureStderr : List String -> BackendTaskTest a -> BackendTaskTest a
ensureStderr expectedMessages =
    ensureOutputWith
        (\outputs ->
            let
                unexpected =
                    List.filterMap isStdoutOutput outputs

                expected =
                    List.filterMap isStderrOutput outputs
            in
            if not (List.isEmpty unexpected) then
                Expect.fail
                    ("ensureStderr found unexpected stdout output:\n\n"
                        ++ formatStringList unexpected
                        ++ "\n\nUse ensureOutputWith to check both stdout and stderr together."
                    )

            else
                Expect.equal expectedMessages expected
        )


isStdoutOutput : Output -> Maybe String
isStdoutOutput output =
    case output of
        Stdout msg ->
            Just msg

        Stderr _ ->
            Nothing


isStderrOutput : Output -> Maybe String
isStderrOutput output =
    case output of
        Stderr msg ->
            Just msg

        Stdout _ ->
            Nothing


formatStringList : List String -> String
formatStringList msgs =
    msgs
        |> List.map (\msg -> "    \"" ++ msg ++ "\"")
        |> String.join "\n"


{-| Assert on interleaved stdout/stderr output, preserving ordering.
Drains on success, preserves on failure.

    import Test.BackendTask as BackendTaskTest exposing (Output(..))

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureOutputWith
            (\outputs ->
                Expect.equal
                    [ Stdout "step 1", Stderr "warning!", Stdout "step 2" ]
                    outputs
            )
        |> BackendTaskTest.expectSuccess

-}
ensureOutputWith : (List Output -> Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensureOutputWith checkOutputs =
    Internal.ensureOutputWith
        (\internalOutputs ->
            checkOutputs (List.map convertOutput internalOutputs)
        )


convertOutput : Internal.Output -> Output
convertOutput output =
    case output of
        Internal.Stdout msg ->
            Stdout msg

        Internal.Stderr msg ->
            Stderr msg



-- FILE ASSERTIONS


{-| Assert that a file exists in the virtual filesystem with the given content.

    Script.writeFile { path = "output.txt", body = "hello" }
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureFile "output.txt" "hello"
        |> BackendTaskTest.expectSuccess

-}
ensureFile : String -> String -> BackendTaskTest a -> BackendTaskTest a
ensureFile =
    Internal.ensureFile


{-| Assert that a file exists in the virtual filesystem (without checking its content).
-}
ensureFileExists : String -> BackendTaskTest a -> BackendTaskTest a
ensureFileExists =
    Internal.ensureFileExists


{-| Assert that a file does not exist in the virtual filesystem.
-}
ensureNoFile : String -> BackendTaskTest a -> BackendTaskTest a
ensureNoFile =
    Internal.ensureNoFile


{-| Assert that a file write occurred with the given path and body.

    Script.writeFile { path = "out.json", body = """{"key":"value"}""" }
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureFileWritten { path = "out.json", body = """{"key":"value"}""" }
        |> BackendTaskTest.expectSuccess

-}
ensureFileWritten : { path : String, body : String } -> BackendTaskTest a -> BackendTaskTest a
ensureFileWritten =
    Internal.ensureFileWritten



-- HTTP ASSERTIONS


{-| Assert that a GET request to the given URL is currently pending, without resolving it.
Useful for verifying that requests are dispatched in parallel.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureHttpGet "https://api.example.com/a"
        |> BackendTaskTest.ensureHttpGet "https://api.example.com/b"
        |> ...

-}
ensureHttpGet : String -> BackendTaskTest a -> BackendTaskTest a
ensureHttpGet url =
    Internal.ensureHttpGet url


{-| Assert that a POST request to the given URL is currently pending, and run an
assertion on the request body. Does not resolve the request.

    import Expect
    import Json.Decode as Decode
    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureHttpPost "https://api.example.com/items"
            (\body ->
                Decode.decodeValue (Decode.field "name" Decode.string) body
                    |> Expect.equal (Ok "test")
            )
        |> ...

-}
ensureHttpPost : String -> (Encode.Value -> Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensureHttpPost url bodyAssertion =
    Internal.ensureHttpPost url bodyAssertion



-- CUSTOM PORT ASSERTIONS


{-| Assert that a `BackendTask.Custom.run` call with the given port name is currently
pending, and run an assertion on the input arguments. Does not resolve the request.

    import Expect
    import Json.Decode as Decode
    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureCustom "hashPassword"
            (\args ->
                Decode.decodeValue Decode.string args
                    |> Expect.equal (Ok "secret123")
            )
        |> ...

-}
ensureCustom : String -> (Encode.Value -> Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensureCustom portName bodyAssertion =
    Internal.ensureCustom portName bodyAssertion



-- COMMAND ASSERTIONS


{-| Assert that a command with the given name is currently pending, and run an
assertion on its arguments. Does not resolve the request. Useful for verifying
commands are called with expected arguments before simulating them.

    import Test.BackendTask as BackendTaskTest

    Script.exec "elm" [ "make", "--docs=docs.json" ]
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureCommand "elm"
            (\args -> Expect.equal [ "make", "--docs=docs.json" ] args)
        |> BackendTaskTest.simulateCommand "elm" ""
        |> BackendTaskTest.expectSuccess

-}
ensureCommand : String -> (List String -> Expectation) -> BackendTaskTest a -> BackendTaskTest a
ensureCommand commandName argsAssertion =
    Internal.ensureCommand commandName argsAssertion



-- VIRTUAL EFFECTS


{-| An effect on the virtual filesystem declared by an opaque external operation
(shell command or `BackendTask.Custom.run` call) via [`withVirtualEffects`](#withVirtualEffects).
Create values with [`writeFileEffect`](#writeFileEffect) and [`removeFileEffect`](#removeFileEffect).
-}
type SimulatedEffect
    = SimulatedEffect Internal.SimulatedEffect


{-| Declare virtual filesystem effects for opaque external operations. The handler
receives the operation name (port name or command name) and request body, and returns
a list of [`SimulatedEffect`](#SimulatedEffect)s applied to the virtual filesystem
when the operation is simulated. For custom ports the body is the JSON input passed to
`BackendTask.Custom.run`. For commands the body is the args as a JSON list of strings.

This fires for both [`simulateCustom`](#simulateCustom) and
[`simulateCommand`](#simulateCommand).

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.withVirtualEffects
            (\name _ ->
                case name of
                    "mkdir" ->
                        [ BackendTaskTest.writeFileEffect "new-dir/.gitkeep" "" ]

                    "generateReport" ->
                        [ BackendTaskTest.writeFileEffect "report.pdf" "content" ]

                    _ ->
                        []
            )
        |> BackendTaskTest.simulateCommand "mkdir" ""
        |> BackendTaskTest.ensureFileExists "new-dir/.gitkeep"
        |> BackendTaskTest.expectSuccess

-}
withVirtualEffects : (String -> Encode.Value -> List SimulatedEffect) -> BackendTaskTest a -> BackendTaskTest a
withVirtualEffects handler =
    Internal.withVirtualEffects
        (\name body ->
            handler name body
                |> List.map (\(SimulatedEffect e) -> e)
        )


{-| Create a simulated file write effect.

    BackendTaskTest.writeFileEffect "output.txt" "file content"

-}
writeFileEffect : String -> String -> SimulatedEffect
writeFileEffect path body =
    SimulatedEffect (Internal.SimWriteFile { path = path, body = body })


{-| Create a simulated file removal effect.

    BackendTaskTest.removeFileEffect "temp.txt"

-}
removeFileEffect : String -> SimulatedEffect
removeFileEffect path =
    SimulatedEffect (Internal.SimRemoveFile path)



-- TERMINAL ASSERTIONS


{-| Assert that the `BackendTask` completed successfully.

    BackendTask.succeed ()
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

If there are still pending requests, the test fails with a message listing them.

-}
expectSuccess : BackendTaskTest a -> Expectation
expectSuccess =
    Internal.expectSuccess


{-| Like [`expectSuccess`](#expectSuccess), but also runs an assertion on the result value.

    BackendTask.succeed 42
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccessWith (Expect.equal 42)

-}
expectSuccessWith : (a -> Expectation) -> BackendTaskTest a -> Expectation
expectSuccessWith =
    Internal.expectSuccessWith


{-| Assert that the `BackendTask` completed with a `FatalError`.
-}
expectFailure : BackendTaskTest a -> Expectation
expectFailure =
    Internal.expectFailure


{-| Like [`expectFailure`](#expectFailure), but also runs an assertion on the error.

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectFailureWith
            (\error -> error.title |> Expect.equal "Http Error")

-}
expectFailureWith : ({ title : String, body : String } -> Expectation) -> BackendTaskTest a -> Expectation
expectFailureWith =
    Internal.expectFailureWith


{-| Assert that the test framework itself produced an error (e.g., a simulation that
didn't match any pending request, or a missing `withTime` configuration).

    BackendTask.Time.now
        |> BackendTask.andThen (\_ -> BackendTask.succeed ())
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectTestError
            (Expect.equal "BackendTask.Time.now requires a virtual time.\\n\\n...")

-}
expectTestError : (String -> Expectation) -> BackendTaskTest a -> Expectation
expectTestError =
    Internal.expectTestError


{-| Assert on the virtual DB state after the script completes. This is a terminal
assertion that also checks the script completed successfully.

    import Expect
    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    myTask
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
expectDb config assertion =
    Internal.expectDb config assertion


