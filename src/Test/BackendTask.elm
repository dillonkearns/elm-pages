module Test.BackendTask exposing
    ( fromBackendTask, fromBackendTaskWith, fromScript, fromScriptWith
    , init, withFile, withBinaryFile, withDb, withDbSetTo, withStdin, withEnv, withTime, withTimeZone, withTimeZoneByName, withRandomSeed, withWhich
    , TimeZone, utc, fixedOffsetZone, customTimeZone
    , simulateHttpGet, simulateHttpPost, simulateHttp, simulateHttpError, HttpError(..), simulateCustom, simulateCommand, simulateCustomStream, simulateStreamHttp
    , simulateQuestion, simulateReadKey
    , ensureHttpGet, ensureHttpPost, ensureCustom, ensureFileWritten
    , Output(..), ensureStdout, ensureStderr, ensureOutputWith
    , ensureFile, ensureFileExists, ensureNoFile
    , SimulatedEffect, withVirtualEffects, writeFileEffect, removeFileEffect
    , expectSuccess, expectSuccessWith, expectDb, expectFailure, expectFailureWith, expectTestError
    )

{-| Write pure tests for your `BackendTask`s and `Script`s that you can run with `elm-test`.
No HTTP calls, no file I/O, or side effects of any kind. Just regular Elm tests.

Common scripting tasks like file operations, logging, and environment variables
are emulated for you. You only need to tell the test how to simulate unpredictable
events in the outside world (like HTTP responses and shell commands), and what starting
state you want for your file system and environment variables. Everything
else will be emulated for you.

You can test a [`BackendTask`](BackendTask) directly using [`fromBackendTask`](#fromBackendTask)
and [`fromBackendTaskWith`](#fromBackendTaskWith). For a more organized API, see the
sub-modules:

  - [`Test.BackendTask.Http`](Test-BackendTask-Http) -- simulate HTTP requests
  - [`Test.BackendTask.Db`](Test-BackendTask-Db) -- seed/assert virtual DB
  - [`Test.BackendTask.Custom`](Test-BackendTask-Custom) -- simulate `BackendTask.Custom.run`
  - [`Test.BackendTask.Stream`](Test-BackendTask-Stream) -- simulate stream pipelines
  - [`Test.BackendTask.Time`](Test-BackendTask-Time) -- configure virtual time zones
  - [`Test.Script`](Test-Script) -- test full Scripts with CLI args


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


## Testing a [`Script`](Pages-Script) with [`fromScript`](#fromScript)

You can also test a full `Script` (including CLI option parsing) by using
[`fromScript`](#fromScript). This gives you the most realistic test since
everything runs through the same entry point as production, with only
external effects simulated.

    generateDotEnvScript : Script
    generateDotEnvScript =
        Script.withCliOptions
            (OptionsParser.build identity
                |> OptionsParser.with
                    (Option.optionalKeywordArg "output")
            )
            (\maybeOutput ->
                generateDotEnv
                    (maybeOutput |> Maybe.withDefault ".env")
            )

    test "writes to custom output path" <|
        \() ->
            generateDotEnvScript
                |> BackendTaskTest.fromScriptWith
                    (BackendTaskTest.init
                        |> BackendTaskTest.withFile "config.json"
                            """{"host": "localhost", "port": 3000, "debug": true}"""
                    )
                    [ "--output", ".env.staging" ]
                |> BackendTaskTest.ensureFile ".env.staging"
                    "HOST=localhost\nPORT=3000\nDEBUG=true"
                |> BackendTaskTest.expectSuccess


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
  - `BackendTask.Time.zone`, `BackendTask.Time.zoneFor`, `BackendTask.Time.zoneByName`, `BackendTask.Time.zoneByNameFor` ([`withTimeZone`](#withTimeZone) / [`withTimeZoneByName`](#withTimeZoneByName) sets initial state)
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
which you [must simulate in order to give the test runner the fake responses and effects to trigger when it runs](#simulating-effects).
If your test case encounters one of these which is not simulated, it will fail with a clear message with instructions for how to
simulate it.


## Building

@docs fromBackendTask, fromBackendTaskWith, fromScript, fromScriptWith


## Test Setup

Seed initial state before the test starts running.

@docs init, withFile, withBinaryFile, withDb, withDbSetTo, withStdin, withEnv, withTime, withTimeZone, withTimeZoneByName, withRandomSeed, withWhich

@docs TimeZone, utc, fixedOffsetZone, customTimeZone


## Simulating Effects

Provide responses for effects the framework can't predict.

  - `BackendTask.Http.*` -> [`simulateHttpGet`](#simulateHttpGet), [`simulateHttpPost`](#simulateHttpPost), [`simulateHttp`](#simulateHttp), [`simulateHttpError`](#simulateHttpError)
  - `BackendTask.Custom.run` -> [`simulateCustom`](#simulateCustom)
  - `Stream.command` / `Script.command` / `Script.exec` -> [`simulateCommand`](#simulateCommand)
  - `Stream.customRead` / `Stream.customWrite` / `Stream.customDuplex` -> [`simulateCustomStream`](#simulateCustomStream)
  - `Stream.http` / `Stream.httpWithInput` -> [`simulateStreamHttp`](#simulateStreamHttp)

@docs simulateHttpGet, simulateHttpPost, simulateHttp, simulateHttpError, HttpError, simulateCustom, simulateCommand, simulateCustomStream, simulateStreamHttp

@docs simulateQuestion, simulateReadKey


## Assertions

Check conditions mid-pipeline without ending the test. These return the same
`BackendTaskTest` so you can keep chaining.

@docs ensureHttpGet, ensureHttpPost, ensureCustom, ensureFileWritten

@docs Output, ensureStdout, ensureStderr, ensureOutputWith

@docs ensureFile, ensureFileExists, ensureNoFile


## Virtual Effects

Declare virtual effects for CustomBackendTask calls. Today these effects update the
virtual filesystem. When a call is resolved
via [`simulateCustom`](#simulateCustom), the registered handler's effects are applied to the
virtual filesystem automatically.

@docs SimulatedEffect, withVirtualEffects, writeFileEffect, removeFileEffect


## Terminal Assertions

Every test must end with exactly one of these to produce an `Expectation`.

@docs expectSuccess, expectSuccessWith, expectDb, expectFailure, expectFailureWith, expectTestError

-}

import BackendTask exposing (BackendTask)
import Bytes exposing (Bytes)
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Json.Encode as Encode
import Pages.Script exposing (Script)
import Test.BackendTask.Internal as Internal exposing (BackendTaskTest, TestSetup)
import Time



-- TYPES


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


{-| The type of HTTP error to simulate with [`simulateHttpError`](#simulateHttpError).

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.simulateHttpError
        "GET"
        "https://api.example.com/data"
        BackendTaskTest.NetworkError

-}
type HttpError
    = NetworkError
    | Timeout


{-| Represents a time zone for use in tests. Create values with [`utc`](#utc),
[`fixedOffsetZone`](#fixedOffsetZone), or [`customTimeZone`](#customTimeZone).
-}
type TimeZone
    = TimeZone Internal.TimeZoneData



-- BUILDING


{-| Start a test from a `BackendTask FatalError a`. Internal effects like `Script.log`
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
    Internal.fromBackendTask


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
fromBackendTaskWith =
    Internal.fromBackendTaskWith


{-| Start a test from a [`Script`](Pages-Script#Script) value with simulated CLI arguments.
This lets you test the full script including CLI option parsing.

    import Pages.Script as Script exposing (Script)
    import Test.BackendTask as BackendTaskTest

    helloScript : Script
    helloScript =
        Script.withoutCliOptions (Script.log "Hello!")

    helloScript
        |> BackendTaskTest.fromScript []
        |> BackendTaskTest.ensureStdout [ "Hello!" ]
        |> BackendTaskTest.expectSuccess

If the CLI arguments don't match the expected options, you get a `TestError`
with the CLI parser's error message.

-}
fromScript : List String -> Script -> BackendTaskTest ()
fromScript =
    Internal.fromScript


{-| Like [`fromScript`](#fromScript) but with a configured [`TestSetup`](#TestSetup).

    import Pages.Script as Script exposing (Script)
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


{-| An empty test setup with no seeded files or DB state.
-}
init : TestSetup
init =
    Internal.init


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
withFile =
    Internal.withFile


{-| Seed a binary file into the virtual filesystem before the test starts running.
Use this for testing `BackendTask.File.binaryFile`.

    import Bytes.Encode
    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withBinaryFile "data.bin"
            (Bytes.Encode.encode (Bytes.Encode.unsignedInt8 42))

-}
withBinaryFile : String -> Bytes -> TestSetup -> TestSetup
withBinaryFile =
    Internal.withBinaryFile


{-| Seed the virtual DB with the default seed value from the generated `testConfig`.
This is the value produced by running the full migration chain from `V1.seed ()`.

Use [`withDbSetTo`](#withDbSetTo) instead when you need a specific initial value.

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


{-| Seed the virtual DB with a specific initial value before the test starts running.

    import Pages.Db
    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withDbSetTo { counter = 0 } Pages.Db.testConfig

-}
withDbSetTo :
    db
    -> { a | schemaVersion : Int, schemaHash : String, encode : db -> Bytes }
    -> TestSetup
    -> TestSetup
withDbSetTo =
    Internal.withDbSetTo


{-| Seed stdin content for stream pipelines that read from `Stream.stdin`.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withStdin "hello from stdin"

-}
withStdin : String -> TestSetup -> TestSetup
withStdin =
    Internal.withStdin


{-| Seed an environment variable for `BackendTask.Env.get` and `BackendTask.Env.expect`.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withEnv "API_KEY" "secret123"

-}
withEnv : String -> String -> TestSetup -> TestSetup
withEnv =
    Internal.withEnv


{-| Set a fixed virtual time for `BackendTask.Time.now`. Without this, any use of
`BackendTask.Time.now` will produce a test error with a helpful message.

    import Time
    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withTime (Time.millisToPosix 1709827200000)

-}
withTime : Time.Posix -> TestSetup -> TestSetup
withTime =
    Internal.withTime


{-| Set the default virtual time zone for `BackendTask.Time.zone` and
`BackendTask.Time.zoneFor`.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withTimeZone BackendTaskTest.utc

-}
withTimeZone : TimeZone -> TestSetup -> TestSetup
withTimeZone (TimeZone tz) =
    Internal.withTimeZone tz


{-| Register a named time zone for `BackendTask.Time.zoneByName` and
`BackendTask.Time.zoneByNameFor`.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withTimeZoneByName "America/Chicago"
            (BackendTaskTest.fixedOffsetZone -360)
        |> BackendTaskTest.withTimeZoneByName "Asia/Kolkata"
            (BackendTaskTest.fixedOffsetZone 330)

-}
withTimeZoneByName : String -> TimeZone -> TestSetup -> TestSetup
withTimeZoneByName name (TimeZone tz) =
    Internal.withTimeZoneByName name tz


{-| Set a fixed random seed for `BackendTask.Random.int32` and `BackendTask.Random.generate`.
Without this, any use of `BackendTask.Random` will produce a test error with a helpful message.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withRandomSeed 42

-}
withRandomSeed : Int -> TestSetup -> TestSetup
withRandomSeed =
    Internal.withRandomSeed


{-| Register a command as available for `Script.which` and `Script.expectWhich`.
The first argument is the command name, the second is its full path.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withWhich "node" "/usr/bin/node"

Commands not registered with `withWhich` will return `Nothing` from `Script.which`.

-}
withWhich : String -> String -> TestSetup -> TestSetup
withWhich =
    Internal.withWhich


{-| UTC time zone (offset 0).

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.init
        |> BackendTaskTest.withTimeZone BackendTaskTest.utc

-}
utc : TimeZone
utc =
    TimeZone { defaultOffset = 0, eras = [] }


{-| A time zone with a fixed offset in minutes from UTC. Negative values are
west of UTC (e.g., -300 for US Eastern Standard Time).

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.fixedOffsetZone -300

-}
fixedOffsetZone : Int -> TimeZone
fixedOffsetZone offsetMinutes =
    TimeZone { defaultOffset = offsetMinutes, eras = [] }


{-| A time zone with a default offset and a list of era transitions. Each era
specifies a start time (milliseconds since epoch) and its UTC offset in minutes.

    import Test.BackendTask as BackendTaskTest

    BackendTaskTest.customTimeZone -300
        [ { start = 1710057600000, offset = -240 } ]

-}
customTimeZone : Int -> List { start : Int, offset : Int } -> TimeZone
customTimeZone defaultOffset eras =
    TimeZone { defaultOffset = defaultOffset, eras = eras }



-- SIMULATING EFFECTS


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
simulateHttpGet =
    Internal.simulateHttpGet


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
simulateHttpPost =
    Internal.simulateHttpPost


{-| General-purpose HTTP simulation. Supports any HTTP method, any status code,
custom response headers, and a response body.

    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    myTask
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
simulateHttp =
    Internal.simulateHttp


{-| Simulate a pending HTTP request failing with an [`HttpError`](#HttpError).

    import Test.BackendTask as BackendTaskTest

    myTask
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
    in
    Internal.simulateHttpError method url errorString


{-| Simulate a pending `BackendTask.Custom.run` call resolving with the given JSON value.
The port name must exactly match the first argument passed to `BackendTask.Custom.run`.

    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCustom "hashPassword"
            (Encode.string "hashed_secret123")
        |> BackendTaskTest.expectSuccess

-}
simulateCustom : String -> Encode.Value -> BackendTaskTest a -> BackendTaskTest a
simulateCustom =
    Internal.simulateCustom


{-| Simulate a pending stream pipeline that contains a `Stream.command`. The framework
handles simulatable parts around the command. You only provide the command's output.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCommand "grep" "error: something bad\n"
        |> BackendTaskTest.expectSuccess

-}
simulateCommand : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateCommand =
    Internal.simulateCommand


{-| Simulate a pending stream pipeline that contains a custom stream part (`Stream.customRead`,
`Stream.customWrite`, or `Stream.customDuplex`). You only provide its output.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateCustomStream "myTransform" "transformed output"
        |> BackendTaskTest.expectSuccess

-}
simulateCustomStream : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateCustomStream =
    Internal.simulateCustomStream


{-| Simulate a pending stream pipeline that contains an HTTP stream part (`Stream.http` or
`Stream.httpWithInput`). You only provide the response body.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateStreamHttp "https://api.example.com" "response body"
        |> BackendTaskTest.expectSuccess

-}
simulateStreamHttp : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateStreamHttp =
    Internal.simulateStreamHttp


{-| Simulate a pending `Script.question` call resolving with the given answer.
The prompt must match the prompt text passed to `Script.question`.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateQuestion "What is your name? " "Dillon"
        |> BackendTaskTest.ensureStdout [ "Hello, Dillon!" ]
        |> BackendTaskTest.expectSuccess

-}
simulateQuestion : String -> String -> BackendTaskTest a -> BackendTaskTest a
simulateQuestion =
    Internal.simulateQuestion


{-| Simulate a pending `Script.readKey` call resolving with the given key.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateReadKey "y"
        |> BackendTaskTest.ensureStdout [ "confirmed" ]
        |> BackendTaskTest.expectSuccess

-}
simulateReadKey : String -> BackendTaskTest a -> BackendTaskTest a
simulateReadKey =
    Internal.simulateReadKey



-- ASSERTIONS


{-| Assert that a GET request to the given URL is currently pending, without resolving it.
This is useful for verifying that requests are issued in parallel.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureHttpGet "https://api.example.com/a"
        |> BackendTaskTest.ensureHttpGet "https://api.example.com/b"
        |> ...

-}
ensureHttpGet : String -> BackendTaskTest a -> BackendTaskTest a
ensureHttpGet =
    Internal.ensureHttpGet


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
ensureHttpPost =
    Internal.ensureHttpPost


{-| Assert that a `BackendTask.Custom.run` call with the given port name is currently pending,
and run an assertion on the arguments. Does not resolve the request.

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
ensureCustom =
    Internal.ensureCustom


{-| Assert that exactly these stdout messages were produced since the last successful
`ensureStdout`, `ensureStderr`, or `ensureOutputWith` call (or since the start of the test).
On success, all output (stdout and stderr) is drained.

    import Test.BackendTask as BackendTaskTest

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


{-| Assert that exactly these stderr messages were produced since the last successful
`ensureStdout`, `ensureStderr`, or `ensureOutputWith` call (or since the start of the test).
On success, all output (stdout and stderr) is drained.

    import Test.BackendTask as BackendTaskTest

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


{-| Assert on the interleaved stdout/stderr output since the last drain, preserving
the ordering between stdout and stderr messages. Drains on success, preserves on failure.

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


{-| Assert that a file exists in the virtual filesystem with the given content.

    import Test.BackendTask as BackendTaskTest

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

    BackendTaskTest.ensureFileExists "output.txt"

-}
ensureFileExists : String -> BackendTaskTest a -> BackendTaskTest a
ensureFileExists =
    Internal.ensureFileExists


{-| Assert that a file does not exist in the virtual filesystem.

    BackendTaskTest.ensureNoFile "output.txt"

-}
ensureNoFile : String -> BackendTaskTest a -> BackendTaskTest a
ensureNoFile =
    Internal.ensureNoFile


{-| Assert that a file was written with the given path and body via `Script.writeFile`.
Both the path and body must match exactly.

    import Test.BackendTask as BackendTaskTest

    Script.writeFile { path = "output.json", body = """{"key":"value"}""" }
        |> BackendTask.allowFatal
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.ensureFileWritten
            { path = "output.json", body = """{"key":"value"}""" }
        |> BackendTaskTest.expectSuccess

-}
ensureFileWritten : { path : String, body : String } -> BackendTaskTest a -> BackendTaskTest a
ensureFileWritten =
    Internal.ensureFileWritten



-- VIRTUAL EFFECTS


{-| Declare virtual effects for CustomBackendTask calls. The handler receives the port name
and the request body (as JSON), and returns a list of [`SimulatedEffect`](#SimulatedEffect)s
to apply when the port is resolved via [`simulateCustom`](#simulateCustom).

    import Json.Encode as Encode
    import Test.BackendTask as BackendTaskTest

    myTask
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
withVirtualEffects handler =
    Internal.withVirtualEffects
        (\portName body ->
            handler portName body
                |> List.map convertSimulatedEffect
        )


convertSimulatedEffect : SimulatedEffect -> Internal.SimulatedEffect
convertSimulatedEffect effect =
    case effect of
        SimWriteFile record ->
            Internal.SimWriteFile record

        SimRemoveFile path ->
            Internal.SimRemoveFile path


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



-- TERMINAL ASSERTIONS


{-| Assert that the `BackendTask` completed successfully. This is a terminal assertion.
It produces an `Expectation` for elm-test, so it should be the last step in your pipeline.

    import Test.BackendTask as BackendTaskTest

    BackendTask.succeed ()
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccess

If the `BackendTask` still has pending requests, the test fails with a message listing them.

-}
expectSuccess : BackendTaskTest a -> Expectation
expectSuccess =
    Internal.expectSuccess


{-| Like [`expectSuccess`](#expectSuccess), but also runs an assertion on the
result value.

    import Expect
    import Test.BackendTask as BackendTaskTest

    BackendTask.succeed 42
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectSuccessWith (Expect.equal 42)

-}
expectSuccessWith : (a -> Expectation) -> BackendTaskTest a -> Expectation
expectSuccessWith =
    Internal.expectSuccessWith


{-| Assert on the virtual DB state. This is a terminal assertion that also checks
the script completed successfully. Pass the generated `Pages.Db.testConfig` and
an assertion function that receives the decoded DB value.

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
expectDb =
    Internal.expectDb


{-| Assert that the `BackendTask` completed with a `FatalError`.

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.simulateHttpError
            "GET"
            "https://api.example.com/data"
            BackendTaskTest.NetworkError
        |> BackendTaskTest.expectFailure

-}
expectFailure : BackendTaskTest a -> Expectation
expectFailure =
    Internal.expectFailure


{-| Like [`expectFailure`](#expectFailure), but also runs an assertion on the
[`FatalError`](FatalError#FatalError).

    import Test.BackendTask as BackendTaskTest

    myTask
        |> BackendTaskTest.fromBackendTask
        |> BackendTaskTest.expectFailureWith
            (\error ->
                error.title
                    |> String.contains "Http"
                    |> Expect.equal True
            )

-}
expectFailureWith : ({ title : String, body : String } -> Expectation) -> BackendTaskTest a -> Expectation
expectFailureWith =
    Internal.expectFailureWith


{-| Assert that the test itself produced an error. For example, a `simulateHttpGet` call
that didn't match any pending request.

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
expectTestError =
    Internal.expectTestError
