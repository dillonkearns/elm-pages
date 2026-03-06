module ScriptTest exposing
    ( ScriptTest
    , fromBackendTask
    , simulateHttpGet
    , ensureHttpGet
    , ensureLogged
    , ensureFileWritten
    , expectSuccess
    , expectFailure
    , expectTestError
    )

import BackendTask exposing (BackendTask)
import Dict
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.StaticHttp.Request as Request
import Pages.StaticHttpRequest exposing (RawRequest(..), Status(..))
import RequestsAndPending


type ScriptTest
    = Running
        { continuation : RawRequest FatalError ()
        , responseEntries : List ( String, Encode.Value )
        , pendingRequests : List Request.Request
        , trackedEffects : List TrackedEffect
        }
    | Done
        { result : Result FatalError ()
        , trackedEffects : List TrackedEffect
        }
    | TestError String


type TrackedEffect
    = LogEffect String
    | FileWriteEffect { path : String, body : String }


fromBackendTask : BackendTask FatalError () -> ScriptTest
fromBackendTask task =
    advanceWithAutoResolve
        { continuation = task
        , responseEntries = []
        , pendingRequests = []
        , trackedEffects = []
        }


type alias RunningState =
    { continuation : RawRequest FatalError ()
    , responseEntries : List ( String, Encode.Value )
    , pendingRequests : List Request.Request
    , trackedEffects : List TrackedEffect
    }


advanceWithAutoResolve : RunningState -> ScriptTest
advanceWithAutoResolve state =
    advanceWithAutoResolveHelper 1000 state


advanceWithAutoResolveHelper : Int -> RunningState -> ScriptTest
advanceWithAutoResolveHelper fuel state =
    if fuel <= 0 then
        TestError "ScriptTest: Too many auto-resolve steps. Does your BackendTask have an infinite loop?"

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
                    }

            HasPermanentError err ->
                TestError (permanentErrorToString err)

            Incomplete pendingRequests continuation ->
                let
                    ( autoResolvable, external ) =
                        List.partition isAutoResolvable pendingRequests

                    ( autoEntries, newEffects ) =
                        buildAutoResponses autoResolvable
                in
                if List.isEmpty external && not (List.isEmpty autoResolvable) then
                    advanceWithAutoResolveHelper (fuel - 1)
                        { continuation = continuation
                        , responseEntries = state.responseEntries ++ autoEntries
                        , pendingRequests = []
                        , trackedEffects = state.trackedEffects ++ newEffects
                        }

                else
                    Running
                        { continuation = continuation
                        , responseEntries = state.responseEntries ++ autoEntries
                        , pendingRequests = external
                        , trackedEffects = state.trackedEffects ++ newEffects
                        }


isAutoResolvable : Request.Request -> Bool
isAutoResolvable request =
    let
        url =
            request.url
    in
    String.startsWith "elm-pages-internal://" url
        && (url /= "elm-pages-internal://port")


buildAutoResponses : List Request.Request -> ( List ( String, Encode.Value ), List TrackedEffect )
buildAutoResponses requests =
    List.foldl
        (\req ( entries, effects ) ->
            let
                hash =
                    Request.hash req

                responseValue =
                    Encode.object
                        [ ( "bodyKind", Encode.string "json" )
                        , ( "body", Encode.null )
                        ]

                entry =
                    ( hash, Encode.object [ ( "response", responseValue ) ] )

                newEffects =
                    trackEffect req
            in
            ( entry :: entries, effects ++ newEffects )
        )
        ( [], [] )
        requests


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


simulateHttpGet : String -> Encode.Value -> ScriptTest -> ScriptTest
simulateHttpGet url jsonResponse scriptTest =
    case scriptTest of
        Running state ->
            case findMatchingRequest "GET" url state.pendingRequests of
                Just ( matchedReq, remaining ) ->
                    let
                        hash =
                            Request.hash matchedReq

                        responseValue =
                            Encode.object
                                [ ( "statusCode", Encode.int 200 )
                                , ( "statusText", Encode.string "OK" )
                                , ( "headers", Encode.object [] )
                                , ( "url", Encode.string url )
                                , ( "bodyKind", Encode.string "json" )
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
                        ("simulateHttpGet: Expected a pending GET request for\n\n    "
                            ++ url
                            ++ "\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )

        Done _ ->
            TestError "simulateHttpGet: The script has already completed. No pending requests to simulate."

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


formatPendingRequests : List Request.Request -> String
formatPendingRequests requests =
    if List.isEmpty requests then
        "    (none)"

    else
        requests
            |> List.map (\req -> "    " ++ req.method ++ " " ++ req.url)
            |> String.join "\n"


ensureHttpGet : String -> ScriptTest -> ScriptTest
ensureHttpGet url scriptTest =
    case scriptTest of
        TestError _ ->
            scriptTest

        Done _ ->
            TestError
                ("ensureHttpGet: Expected a pending GET request for\n\n    "
                    ++ url
                    ++ "\n\nbut the script has already completed."
                )

        Running state ->
            case findMatchingRequest "GET" url state.pendingRequests of
                Just _ ->
                    scriptTest

                Nothing ->
                    TestError
                        ("ensureHttpGet: Expected a pending GET request for\n\n    "
                            ++ url
                            ++ "\n\nbut the pending requests are:\n\n"
                            ++ formatPendingRequests state.pendingRequests
                        )


ensureLogged : String -> ScriptTest -> ScriptTest
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


ensureFileWritten : { path : String, body : String } -> ScriptTest -> ScriptTest
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


permanentErrorToString : Pages.StaticHttpRequest.Error -> String
permanentErrorToString err =
    case err of
        Pages.StaticHttpRequest.DecoderError msg ->
            "Decoder error: " ++ msg

        Pages.StaticHttpRequest.UserCalledStaticHttpFail msg ->
            msg

        Pages.StaticHttpRequest.InternalFailure _ ->
            "Internal error"


expectSuccess : ScriptTest -> Expectation
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


expectFailure : ScriptTest -> Expectation
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


expectTestError : (String -> Expectation) -> ScriptTest -> Expectation
expectTestError assertion scriptTest =
    case scriptTest of
        TestError msg ->
            assertion msg

        Done _ ->
            Expect.fail "Expected a test error, but the script completed."

        Running _ ->
            Expect.fail "Expected a test error, but the script is still running."
