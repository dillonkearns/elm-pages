module Test.BackendTask exposing
    ( BackendTaskTest
    , HttpError(..)
    , fromBackendTask
    , fromScript
    , simulateHttpGet
    , simulateHttpPost
    , simulateHttpError
    , simulateCustom
    , ensureHttpGet
    , ensureHttpPost
    , ensureCustom
    , ensureLogged
    , ensureFileWritten
    , expectFile
    , expectFileExists
    , expectNoFile
    , expectSuccess
    , expectFailure
    , expectTestError
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

@docs BackendTaskTest, HttpError, fromBackendTask, fromScript


## Simulating Effects

@docs simulateHttpGet, simulateHttpPost, simulateHttpError, simulateCustom


## Inline Assertions

These check conditions mid-pipeline without ending the test. They return the same
`BackendTaskTest` so you can keep chaining.

@docs ensureHttpGet, ensureHttpPost, ensureCustom, ensureLogged, ensureFileWritten


## Virtual Filesystem

Built-in filesystem operations (`Script.writeFile`, `Script.removeFile`, etc.) are tracked
in a virtual filesystem. You can seed initial files and assert on the final state.

@docs expectFile, expectFileExists, expectNoFile


## Terminal Assertions

These end the pipeline and produce an `Expectation` for elm-test.

@docs expectSuccess, expectFailure, expectTestError

-}

import BackendTask exposing (BackendTask)
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
        , pendingRequests : List Request.Request
        , trackedEffects : List TrackedEffect
        , virtualFS : VirtualFS
        }
    | Done
        { result : Result FatalError ()
        , trackedEffects : List TrackedEffect
        , virtualFS : VirtualFS
        }
    | TestError String


type alias VirtualFS =
    { files : Dict String String
    }


emptyVirtualFS : VirtualFS
emptyVirtualFS =
    { files = Dict.empty
    }


type TrackedEffect
    = LogEffect String
    | FileWriteEffect { path : String, body : String }


{-| The type of HTTP error to simulate with [`simulateHttpError`](#simulateHttpError).

    BackendTaskTest.simulateHttpError
        "GET"
        "https://api.example.com/data"
        BackendTaskTest.NetworkError

-}
type HttpError
    = NetworkError
    | Timeout


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
fromBackendTask task =
    advanceWithAutoResolve
        { continuation = task
        , responseEntries = []
        , pendingRequests = []
        , trackedEffects = []
        , virtualFS = emptyVirtualFS
        }


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
fromScript cliArgs (Pages.Internal.Script.Script toConfig) =
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
            fromBackendTask task

        Program.SystemMessage _ message ->
            TestError ("fromScript: CLI argument parsing failed:\n\n" ++ message)


type alias RunningState =
    { continuation : RawRequest FatalError ()
    , responseEntries : List ( String, Encode.Value )
    , pendingRequests : List Request.Request
    , trackedEffects : List TrackedEffect
    , virtualFS : VirtualFS
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
                , rawBytes = Dict.empty
                }
        in
        case Pages.StaticHttpRequest.cacheRequestResolution state.continuation requestsAndPending of
            Complete result ->
                Done
                    { result = result
                    , trackedEffects = state.trackedEffects
                    , virtualFS = state.virtualFS
                    }

            HasPermanentError err ->
                TestError (permanentErrorToString err)

            Incomplete pendingRequests continuation ->
                let
                    ( autoResolvable, external ) =
                        List.partition isAutoResolvable pendingRequests

                    ( autoEntries, newEffects ) =
                        buildAutoResponses state.virtualFS autoResolvable

                    newVirtualFS : VirtualFS
                    newVirtualFS =
                        applyVirtualFSEffects autoResolvable state.virtualFS
                in
                if List.isEmpty external && not (List.isEmpty autoResolvable) then
                    advanceWithAutoResolveHelper (fuel - 1)
                        { continuation = continuation
                        , responseEntries = state.responseEntries ++ autoEntries
                        , pendingRequests = []
                        , trackedEffects = state.trackedEffects ++ newEffects
                        , virtualFS = newVirtualFS
                        }

                else
                    Running
                        { continuation = continuation
                        , responseEntries = state.responseEntries ++ autoEntries
                        , pendingRequests = external
                        , trackedEffects = state.trackedEffects ++ newEffects
                        , virtualFS = newVirtualFS
                        }


isAutoResolvable : Request.Request -> Bool
isAutoResolvable request =
    let
        url =
            request.url
    in
    String.startsWith "elm-pages-internal://" url
        && (url /= "elm-pages-internal://port")


buildAutoResponses : VirtualFS -> List Request.Request -> ( List ( String, Encode.Value ), List TrackedEffect )
buildAutoResponses vfs requests =
    List.foldl
        (\req ( entries, effects ) ->
            let
                hash : String
                hash =
                    Request.hash req

                responseBody : Encode.Value
                responseBody =
                    autoResponseBody vfs req

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
            ( entry :: entries, effects ++ newEffects )
        )
        ( [], [] )
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


applyVirtualFSEffects : List Request.Request -> VirtualFS -> VirtualFS
applyVirtualFSEffects requests vfs =
    List.foldl applyVirtualFSEffect vfs requests


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
                        hash =
                            Request.hash matchedReq

                        responseValue =
                            Encode.object
                                [ ( "bodyKind", Encode.string "json" )
                                , ( "body", jsonResponse )
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
                        ("simulateCustom: Expected a pending BackendTask.Custom.run call for port \""
                            ++ portName
                            ++ "\"\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )

        Done _ ->
            TestError "simulateCustom: The script has already completed. No pending requests to simulate."

        TestError _ ->
            scriptTest


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

                    else
                        "    " ++ req.method ++ " " ++ req.url
                )
            |> String.join "\n"


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


withFile : String -> String -> BackendTaskTest -> BackendTaskTest
withFile path content scriptTest =
    case scriptTest of
        Running state ->
            Running { state | virtualFS = insertFile path content state.virtualFS }

        Done state ->
            Done { state | virtualFS = insertFile path content state.virtualFS }

        TestError _ ->
            scriptTest


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
