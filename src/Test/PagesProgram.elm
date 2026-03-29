module Test.PagesProgram exposing
    ( ProgramTest
    , start, startWithEffects, startPlatform
    , clickButton, clickLink, fillIn, fillInTextarea, check
    , navigateTo, ensureBrowserUrl
    , submitFetcher, submitForm, submitFormTo
    , resolveEffect
    , simulateMsg
    , withSimulatedSubscriptions, simulateIncomingPort
    , ensureViewHas, ensureViewHasNot, ensureView
    , expectViewHas, expectViewHasNot, expectView
    , expectModel
    , within
    , simulateDomEvent
    , simulateCustom
    , simulateHttpGet, simulateHttpPost, simulateHttpError
    , simulateHttpGetTo, simulateHttpPostTo
    , selectOption
    , done
    , Snapshot, StepKind(..), NetworkEntry, NetworkStatus(..), TargetSelector(..), FetcherEntry, FetcherStatus(..), toSnapshots, withModelToString
    )

{-| Test elm-pages programs with realistic simulation.

For full-fidelity route tests, use [`startPlatform`](#startPlatform) with a
generated `TestApp` module. This drives the real elm-pages framework
(`Pages.Internal.Platform`) so that shared data, shared view, navigation,
form submission, and all other framework behavior works identically to
production. Only external I/O (HTTP, shell commands, etc.) is simulated
via a mock resolver.

    import TestApp
    import Test exposing (test)
    import Test.Html.Selector as Selector
    import Test.PagesProgram as PagesProgram

    test "renders index page" <|
        \() ->
            TestApp.start "/" mockData
                |> PagesProgram.ensureViewHas [ Selector.text "Hello!" ]
                |> PagesProgram.done

For simple, self-contained page-state tests that don't need the full framework,
use [`start`](#start) with inline config.

@docs ProgramTest

@docs start, startWithEffects, startPlatform

@docs clickButton, clickLink, fillIn, fillInTextarea, check

@docs resolveEffect

@docs submitFetcher

@docs simulateMsg

@docs withSimulatedSubscriptions, simulateIncomingPort

@docs ensureViewHas, ensureViewHasNot, ensureView

@docs expectViewHas, expectViewHasNot, expectView, expectModel

@docs simulateDomEvent

@docs simulateCustom

@docs simulateHttpGet, simulateHttpPost, simulateHttpError

@docs selectOption

@docs done


## Snapshots

Snapshots record the rendered view at each step of the test pipeline. Use them
with the visual test runner to step through your test in the browser.

@docs Snapshot, StepKind, TargetSelector, NetworkEntry, NetworkStatus, FetcherEntry, FetcherStatus, toSnapshots, withModelToString

-}

import BackendTask exposing (BackendTask)
import CookieJar exposing (CookieJar)
import Browser
import Bytes
import Bytes.Decode
import Bytes.Encode
import Dict
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Form
import Html exposing (Html)
import Html.Attributes
import Http
import Internal.Request
import Pages.Internal.FatalError
import Json.Decode
import Json.Encode as Encode
import PageServerResponse exposing (PageServerResponse(..))
import Pages.ConcurrentSubmission
import Pages.Internal.Msg
import Pages.Internal.Platform as Platform
import Pages.Internal.ResponseSketch as ResponseSketch
import Pages.StaticHttp.Request as StaticHttpRequest
import Test.BackendTask exposing (HttpError(..))
import Test.BackendTask.Internal as BackendTaskTest
import Test.PagesProgram.SimulatedSub as SimulatedSub exposing (SimulatedSub)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Test.Runner
import Test.Runner.Failure
import Time
import Url exposing (Url)
import UrlPath


{-| An in-progress elm-pages program test. Create one with [`start`](#start),
interact with it using simulation and assertion functions, and finalize with
[`done`](#done).
-}
type ProgramTest model msg
    = ProgramTest (State model msg)


type alias State model msg =
    { phase : Phase model msg
    , error : Maybe String
    , snapshots : List Snapshot
    , modelToString : Maybe (model -> String)
    , fetcherExtractor : Maybe (model -> List FetcherEntry)
    , pendingFetcherEffects : List (Resolver model msg)
    , lastReadyModel : Maybe model
    , networkLog : List NetworkEntry
    , subscriptions : Maybe (model -> SimulatedSub msg)
    }


{-| The kind of step that produced a snapshot. Used by the visual test runner
to color-code and categorize steps in the command log.
-}
type StepKind
    = Start
    | Interaction
    | Assertion
    | EffectResolution
    | Error


{-| An HTTP request entry in the network log.
-}
type alias NetworkEntry =
    { method : String
    , url : String
    , status : NetworkStatus
    , stepIndex : Int
    }


{-| Whether an HTTP request was stubbed (resolved via simulate*) or is pending.
-}
type NetworkStatus
    = Stubbed
    | Pending


{-| Describes which DOM element a test interaction targeted, so the visual
test runner can highlight it in the preview.
-}
type TargetSelector
    = ByTagAndText String String
    | ByFormField String String
    | ByLabelText String
    | ById String
    | ByTag String


{-| A snapshot of an in-flight fetcher's state at a point in the test pipeline.
Used by the visual test runner to display fetcher lifecycle timelines.
-}
type alias FetcherEntry =
    { id : String
    , status : FetcherStatus
    , fields : List ( String, String )
    , action : String
    , method : String
    }


{-| The status of a fetcher submission.
-}
type FetcherStatus
    = FetcherSubmitting
    | FetcherReloading
    | FetcherComplete


{-| A snapshot of the program state at a point in the test pipeline. Used by
the visual test runner to step through test execution in the browser.

`body` contains the rendered HTML at this step. `title` is the page title.
`rerender` lets the viewer re-render the view (e.g., at a different size).
`modelState` contains the model as a string if `withModelToString` was used.
`stepKind` categorizes the step for color-coding in the viewer.
`browserUrl` is the URL at the time of the snapshot (if URL tracking is enabled).
`targetElement` identifies the element this step interacted with (for highlighting).

-}
type alias Snapshot =
    { label : String
    , title : String
    , body : List (Html Never)
    , rerender : () -> { title : String, body : List (Html Never) }
    , hasPendingEffects : Bool
    , modelState : Maybe String
    , stepKind : StepKind
    , browserUrl : Maybe String
    , errorMessage : Maybe String
    , pendingEffects : List String
    , networkLog : List NetworkEntry
    , targetElement : Maybe TargetSelector
    , fetcherLog : List FetcherEntry
    }


type Phase model msg
    = Resolving (Resolver model msg)
    | Ready (ReadyState model msg)


{-| Hides the `data` type parameter behind closures so `ProgramTest` only
needs `model` and `msg` type parameters.
-}
type Resolver model msg
    = Resolver
        { advance : Maybe model -> Simulation -> AdvanceResult model msg
        , pendingDescription : String
        , pendingUrls : List String
        }


type Simulation
    = SimHttpGet String Encode.Value
    | SimHttpPost String Encode.Value
    | SimHttpError String String String
    | SimCustom String Encode.Value


type AdvanceResult model msg
    = Advanced (Phase model msg)
    | AdvanceError String


type alias ReadyState model msg =
    { model : model
    , getView : model -> { title : String, body : List (Html msg) }
    , update : msg -> model -> { model : model, effects : List (BackendTask FatalError msg), pendingPhase : Maybe (Phase model msg), fetcherResolvers : List (Resolver model msg) }
    , pendingEffects : List (BackendTask FatalError msg)
    , onNavigate : Maybe (String -> msg)
    , getBrowserUrl : Maybe (model -> String)
    , onFormSubmit : Maybe ({ formId : String, action : String, fields : List ( String, String ), useFetcher : Bool } -> msg)
    , getFormFields : Maybe (model -> List ( String, String ))
    , viewScope : Query.Single msg -> Query.Single msg
    , getModelError : model -> Maybe String
    }



-- START


{-| Start a program test. Provide the same fields as a route module: a `data`
BackendTask, an `init` function, an `update` function, and a `view` function.

The `data` BackendTask is auto-resolved as far as possible. If it has no
external dependencies (HTTP, custom ports, etc.), the page initializes
immediately. Otherwise, use [`simulateHttpGet`](#simulateHttpGet) or similar
to provide responses before asserting on the view.

    PagesProgram.start
        { data = BackendTask.succeed ()
        , init = \() -> ( {}, [] )
        , update = \_ model -> ( model, [] )
        , view = \() model -> { title = "Home", body = [ Html.text "Hello" ] }
        }

-}
start :
    { data : BackendTask FatalError data
    , init : data -> ( model, List (BackendTask FatalError msg) )
    , update : msg -> model -> ( model, List (BackendTask FatalError msg) )
    , view : data -> model -> { title : String, body : List (Html msg) }
    }
    -> ProgramTest model msg
start config =
    let
        bt : BackendTaskTest.BackendTaskTest data
        bt =
            BackendTaskTest.fromBackendTask config.data

        phase : Phase model msg
        phase =
            resolveDataPhase bt config.init config.view config.update

        initSnapshot : List Snapshot
        initSnapshot =
            case phase of
                Ready ready ->
                    let
                        viewResult =
                            ready.getView ready.model
                    in
                    [ { label = "start"
                      , title = viewResult.title
                      , body = (mapViewToSnapshot viewResult).body
                      , rerender = \() -> mapViewToSnapshot (ready.getView ready.model)
                      , hasPendingEffects = not (List.isEmpty ready.pendingEffects)
                      , modelState = Nothing
                      , stepKind = Start
                      , browserUrl = ready.getBrowserUrl |> Maybe.map (\getUrl -> getUrl ready.model)
                      , errorMessage = Nothing
                      , pendingEffects = describeEffects ready.pendingEffects
                      , networkLog = []
                      , targetElement = Nothing
                      , fetcherLog = []
                      }
                    ]

                Resolving _ ->
                    [ { label = "start"
                      , title = "(resolving data...)"
                      , body = []
                      , rerender = \() -> { title = "(resolving data...)", body = [] }
                      , hasPendingEffects = True
                      , modelState = Nothing
                      , stepKind = Start
                      , browserUrl = Nothing
                      , errorMessage = Nothing
                      , pendingEffects = []
                      , networkLog = []
                      , targetElement = Nothing
                      , fetcherLog = []
                      }
                    ]
    in
    ProgramTest
        { phase = phase
        , error = Nothing
        , snapshots = initSnapshot
        , modelToString = Nothing
        , fetcherExtractor = Nothing
        , pendingFetcherEffects = []
        , lastReadyModel = Nothing
        , networkLog = []
        , subscriptions = Nothing
        }



{-| Like `start`, but for programs that use a custom `Effect` type instead of
raw `List (BackendTask FatalError msg)`. This is the pattern used by elm-pages
route modules, where you define your own `Effect msg` type in `app/Effect.elm`.

Provide a function that converts your Effect type into a list of BackendTasks
the test framework can simulate:

    PagesProgram.startWithEffects
        (\effect ->
            case effect of
                Effect.None -> []
                Effect.Batch effects -> List.concatMap myExtract effects
                Effect.FetchApi toMsg ->
                    [ BackendTask.Http.getJson url decoder
                        |> BackendTask.allowFatal
                        |> BackendTask.map toMsg
                    ]
                Effect.Cmd _ -> []  -- Cmd is opaque, use simulateMsg instead
        )
        { data = ...
        , init = \d -> ( model, Effect.none )
        , update = \msg model -> ( newModel, Effect.fetchApi GotResult )
        , view = \d model -> { title = "...", body = [...] }
        }

-}
startWithEffects :
    (effect -> List (BackendTask FatalError msg))
    ->
        { data : BackendTask FatalError data
        , init : data -> ( model, effect )
        , update : msg -> model -> ( model, effect )
        , view : data -> model -> { title : String, body : List (Html msg) }
        }
    -> ProgramTest model msg
startWithEffects extractEffects config =
    start
        { data = config.data
        , init =
            \pageData ->
                let
                    ( model, effect ) =
                        config.init pageData
                in
                ( model, extractEffects effect )
        , update =
            \msg model ->
                let
                    ( newModel, effect ) =
                        config.update msg model
                in
                ( newModel, extractEffects effect )
        , view = config.view
        }


{-| Start a full-fidelity elm-pages test by driving `Pages.Internal.Platform`
directly. The generated `TestApp` module provides the `config` (which is
`Main.config`), so the typical usage is:

    TestApp.start "/" mockData
        |> PagesProgram.ensureViewHas [ Selector.text "Hello" ]
        |> PagesProgram.done

Where `TestApp.start = PagesProgram.startPlatform Main.config`.

BackendTask resolution uses the `Test.BackendTask` virtual filesystem, so
file reads, env vars, time, and other auto-resolvable BackendTasks work
out of the box. File writes in actions automatically update the virtual FS,
and subsequent data resolution sees the updated files.

-}
startPlatform config initialPath testSetup =
    let
        baseUrl =
            "https://localhost:1234"

        initialUrl =
            makeTestUrl baseUrl initialPath

        initialVirtualFs =
            case testSetup of
                BackendTaskTest.TestSetup setup ->
                    setup.virtualFS
    in
    case resolveInitialData config initialUrl initialPath initialVirtualFs of
        InitialDataError errMsg ->
            ProgramTest
                { phase =
                    Resolving
                        (Resolver
                            { advance = \_ _ -> AdvanceError errMsg
                            , pendingDescription = errMsg
                            , pendingUrls = []
                            }
                        )
                , error = Just errMsg
                , snapshots = []
                , modelToString = Nothing
                , fetcherExtractor = Nothing
                , pendingFetcherEffects = []
                , lastReadyModel = Nothing
                , networkLog = []
                , subscriptions = Nothing
                }

        resolvedOrPending ->
            let
                ( vfsAfterInit, initialPhase ) =
                    case resolvedOrPending of
                        InitialDataResolved vfs pageDataBytes ->
                            let
                                ( readyModel, readyEffect ) =
                                    platformUpdateClean config (Platform.FrozenViewsReady (Just pageDataBytes)) initModel

                                ( wrapped, _, _ ) =
                                    processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                        { platformModel = readyModel, virtualFs = vfs, cookieJar = CookieJar.empty, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                        readyEffect
                                        100
                            in
                            ( vfs, Ready (makeReady wrapped) )

                        InitialDataPending vfs sharedData dataBt ->
                            -- Initial data has pending HTTP. Create a custom resolver
                            -- that encodes with HotUpdate (including shared data) when done,
                            -- since the Platform's initial FrozenViewsReady handler requires
                            -- HotUpdate format (RenderPage is rejected for initial loads).
                            let
                                continueInitialData bt =
                                    case bt of
                                        BackendTaskTest.Done doneState ->
                                            case extractPageData config doneState.result of
                                                Just pageData ->
                                                    let
                                                        encodedBytes =
                                                            ResponseSketch.HotUpdate pageData
                                                                sharedData
                                                                Nothing
                                                                |> encodeResponseWithPrefix config

                                                        ( readyModel, readyEffect ) =
                                                            platformUpdateClean config
                                                                (Platform.FrozenViewsReady (Just encodedBytes))
                                                                initModel

                                                        ( processedWrapped, _, _ ) =
                                                            processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                                { platformModel = readyModel, virtualFs = doneState.virtualFS, cookieJar = CookieJar.empty, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                                readyEffect
                                                                100
                                                    in
                                                    Advanced (Ready (makeReady processedWrapped))

                                                Nothing ->
                                                    case doneState.result of
                                                        Ok (ServerResponse serverResponse) ->
                                                            case PageServerResponse.toRedirect serverResponse of
                                                                Just { location } ->
                                                                    let
                                                                        updatedJar =
                                                                            CookieJar.empty
                                                                                |> CookieJar.applySetCookieHeaders
                                                                                    (extractSetCookieHeaders (ServerResponse serverResponse))

                                                                        redirectUrl =
                                                                            makeTestUrl baseUrl (normalizePath location)

                                                                        redirectRoute =
                                                                            config.urlToRoute redirectUrl

                                                                        ( vfsAfterRedirect, redirectDataBt ) =
                                                                            BackendTaskTest.resolveWithVirtualFsPartial
                                                                                doneState.virtualFS
                                                                                (config.data (platformTestRequest (Url.toString redirectUrl) updatedJar) redirectRoute)

                                                                        continueRedirectTargetData rdBt =
                                                                            case rdBt of
                                                                                BackendTaskTest.Done rdDoneState ->
                                                                                    case extractPageData config rdDoneState.result of
                                                                                        Just pageData ->
                                                                                            let
                                                                                                encodedBytes =
                                                                                                    ResponseSketch.HotUpdate pageData
                                                                                                        sharedData
                                                                                                        Nothing
                                                                                                        |> encodeResponseWithPrefix config

                                                                                                redirectPlatformModel =
                                                                                                    { initModel | pendingFrozenViewsUrl = Just redirectUrl }

                                                                                                ( readyModel, readyEffect ) =
                                                                                                    platformUpdateClean config
                                                                                                        (Platform.FrozenViewsReady (Just encodedBytes))
                                                                                                        redirectPlatformModel

                                                                                                ( processedWrapped, _, _ ) =
                                                                                                    processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                                                                        { platformModel = readyModel, virtualFs = rdDoneState.virtualFS, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                                                                        readyEffect
                                                                                                        100
                                                                                            in
                                                                                            Advanced (Ready (makeReady processedWrapped))

                                                                                        Nothing ->
                                                                                            AdvanceError "Failed to extract page data for redirect target"

                                                                                BackendTaskTest.Running rdRunningState ->
                                                                                    Advanced
                                                                                        (Resolving
                                                                                            (Resolver
                                                                                                { advance =
                                                                                                    \_ sim ->
                                                                                                        continueRedirectTargetData (applySimToBt sim rdBt)
                                                                                                , pendingDescription =
                                                                                                    stillRunningDescription rdRunningState.pendingRequests
                                                                                                , pendingUrls =
                                                                                                    List.map .url rdRunningState.pendingRequests
                                                                                                }
                                                                                            )
                                                                                        )

                                                                                BackendTaskTest.TestError rdErrMsg ->
                                                                                    AdvanceError rdErrMsg
                                                                    in
                                                                    continueRedirectTargetData redirectDataBt

                                                                Nothing ->
                                                                    AdvanceError ("Unexpected server response with status " ++ String.fromInt serverResponse.statusCode)

                                                        Err fatalErr ->
                                                            let
                                                                errorPageData =
                                                                    config.errorPageToData (config.internalError (fatalErrorToString fatalErr))

                                                                encodedBytes =
                                                                    ResponseSketch.HotUpdate
                                                                        errorPageData
                                                                        sharedData
                                                                        Nothing
                                                                        |> encodeResponseWithPrefix config

                                                                ( readyModel, readyEffect ) =
                                                                    platformUpdateClean config
                                                                        (Platform.FrozenViewsReady (Just encodedBytes))
                                                                        initModel

                                                                ( processedWrapped, _, _ ) =
                                                                    processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                                        { platformModel = readyModel, virtualFs = doneState.virtualFS, cookieJar = CookieJar.empty, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                                        readyEffect
                                                                        100
                                                            in
                                                            Advanced (Ready (makeReady processedWrapped))

                                                        _ ->
                                                            AdvanceError "Failed to extract page data after initial HTTP simulation"

                                        BackendTaskTest.Running runningState ->
                                            Advanced
                                                (Resolving
                                                    (Resolver
                                                        { advance =
                                                            \_ sim ->
                                                                continueInitialData (applySimToBt sim bt)
                                                        , pendingDescription =
                                                            stillRunningDescription runningState.pendingRequests
                                                        , pendingUrls =
                                                            List.map .url runningState.pendingRequests
                                                        }
                                                    )
                                                )

                                        BackendTaskTest.TestError errMsg ->
                                            AdvanceError errMsg
                            in
                            ( vfs
                            , Resolving
                                (Resolver
                                    { advance =
                                        \_ sim ->
                                            continueInitialData (applySimToBt sim dataBt)
                                    , pendingDescription =
                                        "Initial data pending HTTP"
                                    , pendingUrls =
                                        btPendingUrls dataBt
                                    }
                                )
                            )

                        -- Can't happen (InitialDataError handled above)
                        InitialDataError _ ->
                            ( initialVirtualFs, Ready (makeReady { platformModel = initModel, virtualFs = initialVirtualFs, cookieJar = CookieJar.empty, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing }) )

                flags =
                    Encode.object []

                ( initModel, _ ) =
                    Platform.init config flags initialUrl Nothing

                updateFn msg wrappedModel =
                    let
                        ( newPlatformModel, effectFromUpdate ) =
                            platformUpdateClean config msg wrappedModel.platformModel

                        ( processedWrapped, _, fetcherResolvers ) =
                            processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                { wrappedModel | platformModel = newPlatformModel }
                                effectFromUpdate
                                100
                    in
                    case processedWrapped.pendingDataError of
                        Just _ ->
                            { model = processedWrapped
                            , effects = []
                            , pendingPhase = Just (makePlatformResolver config baseUrl processedWrapped makeReady)
                            , fetcherResolvers = fetcherResolvers
                            }

                        Nothing ->
                            { model = processedWrapped
                            , effects = []
                            , pendingPhase = Nothing
                            , fetcherResolvers = fetcherResolvers
                            }

                makeReady m =
                    { model = m
                    , getView = viewFn
                    , update = updateFn
                    , pendingEffects = []
                    , onNavigate =
                        Just
                            (\href ->
                                Platform.LinkClicked
                                    (Browser.Internal (makeTestUrl baseUrl href))
                            )
                    , getBrowserUrl =
                        Just (\m_ -> Url.toString m_.platformModel.url)
                    , onFormSubmit =
                        Just
                            (\{ formId, action, fields, useFetcher } ->
                                Platform.UserMsg
                                    (Pages.Internal.Msg.Submit
                                        { useFetcher = useFetcher
                                        , action = action
                                        , method = Form.Post
                                        , fields = fields
                                        , msg = Nothing
                                        , id = formId
                                        , valid = True
                                        }
                                    )
                            )
                    , getFormFields =
                        Just
                            (\m_ ->
                                m_.platformModel.pageFormState
                                    |> Dict.values
                                    |> List.concatMap
                                        (\formState ->
                                            formState.fields
                                                |> Dict.toList
                                                |> List.map (\( k, v ) -> ( k, v.value ))
                                        )
                            )
                    , viewScope = identity
                    , getModelError = \m_ -> m_.pendingDataError
                    }

                viewFn wrappedModel =
                    let
                        doc =
                            Platform.view config wrappedModel.platformModel
                    in
                    { title = doc.title, body = doc.body }

                -- Create a Resolving phase for a platform model that paused on HTTP.
                -- Re-resolves the pending BackendTask to get the BackendTaskTest,
                -- then wraps it in a Resolver that uses Test.BackendTask's
                -- simulation mechanism (simulateHttpPost etc.) to advance.
                makePlatformResolver config_ baseUrl_ wrappedModel makeReady_ =
                    let
                        makePhase m =
                            Ready (makeReady_ m)
                    in
                    case wrappedModel.pendingActionBody of
                        Just { body, path } ->
                            -- Action paused on HTTP
                            let
                                fetchUrl =
                                    makeTestUrl baseUrl_ path

                                route =
                                    config_.urlToRoute fetchUrl

                                actionRequest =
                                    Internal.Request.Request
                                        { time = Time.millisToPosix 0
                                        , method = "POST"
                                        , body = Just body
                                        , rawUrl = baseUrl_ ++ path
                                        , rawHeaders =
                                            Dict.singleton "content-type"
                                                "application/x-www-form-urlencoded"
                                        , cookies = CookieJar.toDict wrappedModel.cookieJar
                                        }

                                ( _, bt ) =
                                    BackendTaskTest.resolveWithVirtualFsPartial
                                        wrappedModel.virtualFs
                                        (config_.action actionRequest route)
                            in
                            Resolving
                                (Resolver
                                    { advance =
                                        \_ sim ->
                                            continueActionWithBt config_ baseUrl_ makeReady_ makePlatformResolver continueDataWithBt wrappedModel fetchUrl makePhase (applySimToBt sim bt)
                                    , pendingDescription =
                                        wrappedModel.pendingDataError |> Maybe.withDefault "Pending action HTTP"
                                    , pendingUrls = btPendingUrls bt
                                    }
                                )

                        Nothing ->
                            case wrappedModel.pendingDataPath of
                                Just path ->
                                    -- Data paused on HTTP
                                    let
                                        fetchUrl =
                                            makeTestUrl baseUrl_ path

                                        route =
                                            config_.urlToRoute fetchUrl

                                        ( _, bt ) =
                                            BackendTaskTest.resolveWithVirtualFsPartial
                                                wrappedModel.virtualFs
                                                (config_.data (platformTestRequest (Url.toString fetchUrl) wrappedModel.cookieJar) route)
                                    in
                                    Resolving
                                        (Resolver
                                            { advance =
                                                \_ sim ->
                                                    continueDataWithBt wrappedModel makePhase (applySimToBt sim bt)
                                            , pendingDescription =
                                                wrappedModel.pendingDataError |> Maybe.withDefault "Pending data HTTP"
                                            , pendingUrls = btPendingUrls bt
                                            }
                                        )

                                Nothing ->
                                    -- Shouldn't happen, but fall back to Ready
                                    makePhase wrappedModel

                -- Continue a data navigation once the BackendTaskTest resolves.
                -- makePhase converts a new model into the appropriate Phase.
                -- When Done, encodes the page data and dispatches FrozenViewsReady.
                -- When still Running, creates a Resolver that captures the current
                -- BackendTaskTest directly (no replay of previously-applied sims).
                continueDataWithBt wrappedModel makePhase bt =
                    case bt of
                        BackendTaskTest.Done doneState ->
                            let
                                vfsAfterData =
                                    doneState.virtualFS

                                dataResult =
                                    doneState.result

                            in
                            case extractPageData config dataResult of
                                Just pageData ->
                                    let
                                        encodedBytes =
                                            case wrappedModel.platformModel.pageData of
                                                Ok prevData ->
                                                    ResponseSketch.HotUpdate pageData
                                                        prevData.sharedData
                                                        Nothing
                                                        |> encodeResponseWithPrefix config

                                                Err _ ->
                                                    ResponseSketch.RenderPage pageData Nothing
                                                        |> encodeResponseWithPrefix config

                                        ( newPlatformModel, newEffect ) =
                                            platformUpdateClean config
                                                (Platform.FrozenViewsReady (Just encodedBytes))
                                                wrappedModel.platformModel

                                        cleanedModel =
                                            { newPlatformModel | notFound = Nothing }

                                        ( processedWrapped, _, _ ) =
                                            processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                { platformModel = cleanedModel, virtualFs = vfsAfterData, cookieJar = wrappedModel.cookieJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                newEffect
                                                100

                                    in
                                    Advanced (makePhase processedWrapped)

                                Nothing ->
                                    -- Redirect or non-renderable response
                                    case dataResult of
                                        Ok (ServerResponse serverResponse) ->
                                            case PageServerResponse.toRedirect serverResponse of
                                                Just { location } ->
                                                    let
                                                        encodedBytes =
                                                            ResponseSketch.Redirect location
                                                                |> encodeResponseWithPrefix config

                                                        ( newPlatformModel, newEffect ) =
                                                            platformUpdateClean config
                                                                (Platform.FrozenViewsReady (Just encodedBytes))
                                                                wrappedModel.platformModel

                                                        ( processedWrapped, _, _ ) =
                                                            processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                                { platformModel = newPlatformModel, virtualFs = vfsAfterData, cookieJar = wrappedModel.cookieJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                                newEffect
                                                                100
                                                    in
                                                    Advanced (makePhase processedWrapped)

                                                Nothing ->
                                                    AdvanceError ("Unexpected server response: " ++ String.fromInt serverResponse.statusCode)

                                        Err err ->
                                            AdvanceError (fatalErrorToString err)

                                        _ ->
                                            AdvanceError "Failed to resolve route data after HTTP simulation"

                        BackendTaskTest.Running runningState ->
                            Advanced
                                (Resolving
                                    (Resolver
                                        { advance =
                                            \_ sim ->
                                                continueDataWithBt wrappedModel makePhase (applySimToBt sim bt)
                                        , pendingDescription =
                                            stillRunningDescription runningState.pendingRequests
                                        , pendingUrls =
                                            List.map .url runningState.pendingRequests
                                        }
                                    )
                                )

                        BackendTaskTest.TestError errMsg ->
                            AdvanceError errMsg

                initSnapshots =
                    case initialPhase of
                        Ready readyState ->
                            let
                                viewResult =
                                    readyState.getView readyState.model
                            in
                            [ { label = "start"
                              , title = viewResult.title
                              , body = (mapViewToSnapshot viewResult).body
                              , rerender = \() -> mapViewToSnapshot (readyState.getView readyState.model)
                              , hasPendingEffects = False
                              , modelState = Nothing
                              , stepKind = Start
                              , browserUrl = Just (Url.toString readyState.model.platformModel.url)
                              , errorMessage = Nothing
                              , pendingEffects = []
                              , networkLog = []
                              , targetElement = Nothing
                              , fetcherLog = []
                              }
                            ]

                        Resolving _ ->
                            []

                extractFetchers wrappedModel =
                    wrappedModel.platformModel.inFlightFetchers
                        |> Dict.toList
                        |> List.map
                            (\( fetcherId, ( _, fetcher ) ) ->
                                { id = fetcherId
                                , status =
                                    case fetcher.status of
                                        Pages.ConcurrentSubmission.Submitting ->
                                            FetcherSubmitting

                                        Pages.ConcurrentSubmission.Reloading _ ->
                                            FetcherReloading

                                        Pages.ConcurrentSubmission.Complete _ ->
                                            FetcherComplete
                                , fields = fetcher.payload.fields
                                , action = fetcher.payload.action
                                , method =
                                    case fetcher.payload.method of
                                        Form.Get ->
                                            "GET"

                                        Form.Post ->
                                            "POST"
                                }
                            )
            in
            ProgramTest
                { phase = initialPhase
                , error = Nothing
                , snapshots = initSnapshots
                , modelToString = Nothing
                , fetcherExtractor = Just extractFetchers
                , pendingFetcherEffects = []
                , lastReadyModel = Nothing
                , networkLog = []
                , subscriptions = Nothing
                }



-- SIMULATION


{-| Simulate a pending HTTP GET request resolving with the given JSON response
body. Applies to whichever BackendTask is currently pending (data loading or
action handling).

    PagesProgram.start
        { data = BackendTask.Http.getJson "https://api.example.com/user" userDecoder
        , ...
        }
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/user"
            (Encode.object [ ( "name", Encode.string "Alice" ) ])
        |> PagesProgram.ensureViewHas [ Selector.text "Alice" ]

-}
simulateHttpGet : String -> Encode.Value -> ProgramTest model msg -> ProgramTest model msg
simulateHttpGet url jsonResponse =
    applySimulation (SimHttpGet url jsonResponse)


{-| Simulate a pending `BackendTask.Custom.run` call resolving with the given
JSON response. Provide the port name and the JSON value the port would return.

    TestApp.start "/" setup
        |> PagesProgram.simulateCustom "getTodos"
            (Encode.list todoEncoder myTodos)
        |> PagesProgram.ensureViewHas [ Selector.text "Buy milk" ]

-}
simulateCustom : String -> Encode.Value -> ProgramTest model msg -> ProgramTest model msg
simulateCustom portName jsonResponse =
    applySimulation (SimCustom portName jsonResponse)


{-| Simulate a pending HTTP POST request resolving with the given JSON response
body.
-}
simulateHttpPost : String -> Encode.Value -> ProgramTest model msg -> ProgramTest model msg
simulateHttpPost url jsonResponse =
    applySimulation (SimHttpPost url jsonResponse)


{-| Simulate an HTTP error (network error or timeout) on a pending request.
Use with `Test.BackendTask.HttpError`:

    import Test.BackendTask exposing (HttpError(..))

    PagesProgram.start { data = myHttpBackendTask, ... }
        |> PagesProgram.simulateHttpError "GET" "https://api.example.com/data" NetworkError

-}
simulateHttpError : String -> String -> HttpError -> ProgramTest model msg -> ProgramTest model msg
simulateHttpError method url error =
    let
        errorString =
            case error of
                NetworkError ->
                    "NetworkError"

                Timeout ->
                    "Timeout"
    in
    applySimulation (SimHttpError method url errorString)


{-| Like [`simulateHttpGet`](#simulateHttpGet), but targets the resolver whose
pending URL matches. Use when multiple resolvers are pending for different URLs
and you want to resolve a specific one regardless of queue order.

    test
        |> PagesProgram.simulateHttpGetTo
            "https://api.example.com/count"
            (Encode.object [ ( "count", Encode.int 5 ) ])

-}
simulateHttpGetTo : String -> Encode.Value -> ProgramTest model msg -> ProgramTest model msg
simulateHttpGetTo targetUrl jsonResponse =
    applySimulationToUrl targetUrl (SimHttpGet targetUrl jsonResponse)


{-| Like [`simulateHttpPost`](#simulateHttpPost), but targets the resolver whose
pending URL matches.
-}
simulateHttpPostTo : String -> Encode.Value -> ProgramTest model msg -> ProgramTest model msg
simulateHttpPostTo targetUrl jsonResponse =
    applySimulationToUrl targetUrl (SimHttpPost targetUrl jsonResponse)


{-| Select an option from a dropdown `<select>` element. Follows elm-program-test's
API: provide the element ID, label text, option value, and option text.

    PagesProgram.start counterConfig
        |> PagesProgram.selectOption "color-select" "Favorite Color" "blue" "Blue"
        |> PagesProgram.ensureViewHas [ Selector.text "Selected: blue" ]

-}
selectOption : String -> String -> String -> String -> ProgramTest model msg -> ProgramTest model msg
selectOption fieldId label optionValue optionText (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("selectOption \""
                                        ++ fieldId
                                        ++ "\": Cannot interact while BackendTask data is still resolving."
                                    )
                        }

                Ready ready ->
                    let
                        query : Query.Single msg
                        query =
                            renderScopedView ready

                        selectQuery : Query.Single msg
                        selectQuery =
                            query
                                |> Query.find [ Selector.id fieldId ]

                        eventResult : Result String msg
                        eventResult =
                            selectQuery
                                |> Event.simulate (Event.input optionValue)
                                |> Event.toResult
                    in
                    case eventResult of
                        Ok msg ->
                            applyMsgWithLabel
                                ("selectOption \"" ++ fieldId ++ "\" \"" ++ optionText ++ "\"")
                                Interaction
                                (Just (ById fieldId))
                                msg
                                (ProgramTest state)

                        Err errMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("selectOption \""
                                                ++ fieldId
                                                ++ "\" failed:\n\n"
                                                ++ errMsg
                                            )
                                }


{-| Simulate a DOM event on a targeted element. This is the escape hatch
for events not covered by `clickButton`, `fillIn`, etc.

The first argument narrows the query to find the target element.
The second argument is the event to simulate (from `Test.Html.Event`).

    import Test.Html.Event as Event

    myTest
        |> PagesProgram.simulateDomEvent
            (Query.find [ Selector.id "my-input" ])
            Event.focus

-}
simulateDomEvent : (Query.Single msg -> Query.Single msg) -> ( String, Encode.Value ) -> ProgramTest model msg -> ProgramTest model msg
simulateDomEvent findTarget event (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state | error = Just "simulateDomEvent: Cannot interact while BackendTask data is still resolving." }

                Ready ready ->
                    let
                        targetQuery =
                            renderScopedView ready
                                |> findTarget

                        eventResult =
                            targetQuery
                                |> Event.simulate event
                                |> Event.toResult
                    in
                    case eventResult of
                        Ok msg ->
                            applyMsgWithLabel "simulateDomEvent" Interaction Nothing msg (ProgramTest state)

                        Err errMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just ("simulateDomEvent failed:\n\n" ++ errMsg)
                                }


{-| Register a simulated subscriptions function. The function is called with
the current model each time `simulateIncomingPort` is used, so subscriptions
can be model-dependent (e.g., only listen when connected).

    import Test.PagesProgram.SimulatedSub as SimulatedSub

    myTest
        |> PagesProgram.withSimulatedSubscriptions
            (\model ->
                if model.isConnected then
                    SimulatedSub.port_ "websocketData"
                        (Decode.string |> Decode.map GotMessage)
                else
                    SimulatedSub.none
            )

-}
withSimulatedSubscriptions : (model -> SimulatedSub msg) -> ProgramTest model msg -> ProgramTest model msg
withSimulatedSubscriptions fn (ProgramTest state) =
    ProgramTest { state | subscriptions = Just fn }


{-| Simulate data arriving through an incoming port. The test framework
evaluates the subscription function (registered via `withSimulatedSubscriptions`)
with the current model, finds matching port subscriptions, decodes the value,
and dispatches the resulting message through `update`.

    |> PagesProgram.simulateIncomingPort "websocketData"
        (Encode.string "hello from server")

Fails if:

  - `withSimulatedSubscriptions` was not called
  - The program is not currently subscribed to the named port
  - The value does not match the port's decoder

-}
simulateIncomingPort : String -> Encode.Value -> ProgramTest model msg -> ProgramTest model msg
simulateIncomingPort portName value (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.subscriptions of
                Nothing ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("simulateIncomingPort \""
                                        ++ portName
                                        ++ "\": you must use PagesProgram.withSimulatedSubscriptions before using simulateIncomingPort"
                                    )
                        }

                Just subsFn ->
                    case state.phase of
                        Resolving _ ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("simulateIncomingPort \""
                                                ++ portName
                                                ++ "\": Cannot simulate port while BackendTask is resolving."
                                            )
                                }

                        Ready ready ->
                            let
                                currentSubs =
                                    subsFn ready.model

                                matches =
                                    findPortMatches portName value currentSubs
                            in
                            case matches of
                                [] ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just
                                                    ("simulateIncomingPort \""
                                                        ++ portName
                                                        ++ "\": the program is not currently subscribed to the port \""
                                                        ++ portName
                                                        ++ "\""
                                                    )
                                        }

                                _ ->
                                    List.foldl
                                        (\result programTest ->
                                            case result of
                                                Ok msg ->
                                                    applyMsgWithLabel
                                                        ("simulateIncomingPort \"" ++ portName ++ "\"")
                                                        Interaction
                                                        Nothing
                                                        msg
                                                        programTest

                                                Err decodeError ->
                                                    case programTest of
                                                        ProgramTest s ->
                                                            ProgramTest
                                                                { s
                                                                    | error =
                                                                        Just
                                                                            ("simulateIncomingPort \""
                                                                                ++ portName
                                                                                ++ "\": the value does not match the port's decoder:\n\n"
                                                                                ++ decodeError
                                                                            )
                                                                }
                                        )
                                        (ProgramTest state)
                                        matches


{-| Recursively search a SimulatedSub tree for PortSub entries matching
the given port name. Returns a list of decode results.
-}
findPortMatches : String -> Encode.Value -> SimulatedSub msg -> List (Result String msg)
findPortMatches portName value sub =
    case sub of
        SimulatedSub.NoneSub ->
            []

        SimulatedSub.BatchSub subs ->
            List.concatMap (findPortMatches portName value) subs

        SimulatedSub.PortSub name decoder ->
            if name == portName then
                [ Json.Decode.decodeValue decoder value
                    |> Result.mapError Json.Decode.errorToString
                ]

            else
                []


{-| Dispatch a message directly, as if it came from a subscription.

Elm's `Sub msg` is opaque and can't be fired from test code. Instead of
trying to simulate the subscription itself, send the message that the
subscription would produce. This works for any subscription type:

    -- Time.every produces a Tick message:
    |> PagesProgram.simulateMsg (Tick (Time.millisToPosix 1000))

    -- Browser.Events.onResize produces a Resize message:
    |> PagesProgram.simulateMsg (WindowResized 1920 1080)

    -- An incoming port produces a PortData message:
    |> PagesProgram.simulateMsg (GotWebSocketData "hello")

-}
simulateMsg : msg -> ProgramTest model msg -> ProgramTest model msg
simulateMsg msg programTest =
    applyMsgWithLabel "simulateMsg" Interaction Nothing msg programTest



-- USER INTERACTIONS


{-| Simulate clicking a button with the given text. Finds the first `<button>`
element whose text content matches, simulates a click event, and passes the
resulting message through `update`.

    PagesProgram.start counterConfig
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.ensureViewHas [ Selector.text "1" ]

-}
clickButton : String -> ProgramTest model msg -> ProgramTest model msg
clickButton buttonText (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("clickButton \""
                                        ++ buttonText
                                        ++ "\": Cannot interact while BackendTask data is still resolving."
                                    )
                        }

                Ready ready ->
                    let
                        query : Query.Single msg
                        query =
                            renderScopedView ready

                        -- Check for disabled button first (elm-program-test pattern)
                        disabledButtonExists : Bool
                        disabledButtonExists =
                            query
                                |> Query.has
                                    [ Selector.tag "button"
                                    , Selector.containing [ Selector.text buttonText ]
                                    , Selector.disabled True
                                    ]
                                |> (\expectation -> getFailureMessage expectation == Nothing)
                    in
                    if disabledButtonExists then
                        ProgramTest
                            { state
                                | error =
                                    Just
                                        ("clickButton \""
                                            ++ buttonText
                                            ++ "\" failed: the button is disabled."
                                        )
                            }

                    else
                    let
                        allButtons =
                            query
                                |> Query.findAll
                                    [ Selector.tag "button"
                                    , Selector.containing [ Selector.text buttonText ]
                                    ]

                        hasMultiple : Bool
                        hasMultiple =
                            allButtons
                                |> Query.count (Expect.atMost 1)
                                |> (\expectation -> getFailureMessage expectation /= Nothing)
                    in
                    if hasMultiple then
                        ProgramTest
                            { state
                                | error =
                                    Just
                                        ("clickButton \""
                                            ++ buttonText
                                            ++ "\" found multiple buttons with that text. Use `within` to scope to a specific element, or use unique button text."
                                        )
                            }

                    else
                    let
                        buttonQuery : Query.Single msg
                        buttonQuery =
                            allButtons |> Query.first

                        eventResult : Result String msg
                        eventResult =
                            buttonQuery
                                |> Event.simulate Event.click
                                |> Event.toResult

                        -- Try form submit first (goes through form library's
                        -- onSubmit pipeline, correctly setting useFetcher).
                        formSubmitResult : Result String msg
                        formSubmitResult =
                            let
                                formQuery =
                                    query
                                        |> Query.find
                                            [ Selector.tag "form"
                                            , Selector.containing
                                                [ Selector.tag "button"
                                                , Selector.containing [ Selector.text buttonText ]
                                                ]
                                            ]
                            in
                            formQuery
                                |> Event.simulate
                                    ( "submit"
                                    , Encode.object
                                        [ ( "currentTarget"
                                          , Encode.object
                                                [ ( "method", Encode.string "POST" )
                                                , ( "action", Encode.string "" )
                                                , ( "id", Encode.null )
                                                ]
                                          )
                                        ]
                                    )
                                |> Event.toResult
                    in
                    case formSubmitResult of
                        Ok msg ->
                            applyMsgWithLabel ("clickButton \"" ++ buttonText ++ "\"") Interaction (Just (ByTagAndText "button" buttonText)) msg (ProgramTest state)

                        Err _ ->
                            case eventResult of
                                Ok msg ->
                                    applyMsgWithLabel ("clickButton \"" ++ buttonText ++ "\"") Interaction (Just (ByTagAndText "button" buttonText)) msg (ProgramTest state)

                                Err clickErr ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just
                                                    ("clickButton \""
                                                        ++ buttonText
                                                        ++ "\" failed: no form submit handler or click handler found.\n"
                                                        ++ clickErr
                                                    )
                                        }


{-| Simulate typing text into an input field.

For elm-pages forms, pass the form ID (from `Form.options`) and the field
name (from `Form.field`):

    TestApp.start "/feedback" mockData
        |> PagesProgram.fillIn "feedback-form" "message" "Hello!"
        |> PagesProgram.clickButton "Submit Feedback"

For plain inputs, pass the element's `id` attribute and label text:

    |> PagesProgram.fillIn "email" "Email address" "alice@example.com"

Pass empty string as the first argument to find inputs nested inside
`<label>` elements without an explicit `id`:

    |> PagesProgram.fillIn "" "Username" "alice"

-}
fillIn : String -> String -> String -> ProgramTest model msg -> ProgramTest model msg
fillIn fieldId fieldName value (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("fillIn \""
                                        ++ fieldName
                                        ++ "\": Cannot interact while BackendTask data is still resolving."
                                    )
                        }

                Ready ready ->
                    let
                        query : Query.Single msg
                        query =
                            renderScopedView ready

                        stepLabel =
                            "fillIn \"" ++ fieldName ++ "\""

                        -- Strategy 1: elm-pages form with event delegation.
                        -- Find <form id="fieldId">, simulate input event on it
                        -- with target.name=fieldName and currentTarget.id=fieldId.
                        formDelegationResult : Result String msg
                        formDelegationResult =
                            if fieldId == "" then
                                Err "no form ID"

                            else
                                query
                                    |> Query.find
                                        [ Selector.tag "form"
                                        , Selector.id fieldId
                                        ]
                                    |> Event.simulate
                                        (Event.custom "input"
                                            (Encode.object
                                                [ ( "type", Encode.string "input" )
                                                , ( "target"
                                                  , Encode.object
                                                        [ ( "value", Encode.string value )
                                                        , ( "name", Encode.string fieldName )
                                                        , ( "type", Encode.string "text" )
                                                        , ( "checked", Encode.bool False )
                                                        ]
                                                  )
                                                , ( "currentTarget"
                                                  , Encode.object
                                                        [ ( "id", Encode.string fieldId )
                                                        ]
                                                  )
                                                ]
                                            )
                                        )
                                    |> Event.toResult

                        -- Strategy 2: Input or textarea nested in <label>
                        labelWrappedResult : Result String msg
                        labelWrappedResult =
                            let
                                labelQuery =
                                    query
                                        |> Query.find
                                            [ Selector.tag "label"
                                            , Selector.containing [ Selector.text fieldName ]
                                            ]

                                inputResult =
                                    labelQuery
                                        |> Query.find [ Selector.tag "input" ]
                                        |> Event.simulate (Event.input value)
                                        |> Event.toResult

                                textareaResult =
                                    labelQuery
                                        |> Query.find [ Selector.tag "textarea" ]
                                        |> Event.simulate (Event.input value)
                                        |> Event.toResult
                            in
                            case inputResult of
                                Ok _ ->
                                    inputResult

                                Err _ ->
                                    textareaResult

                        -- Strategy 3: Input or textarea with id
                        idResult : Result String msg
                        idResult =
                            if fieldId == "" then
                                Err "no field ID"

                            else
                                query
                                    |> Query.find
                                        [ Selector.id fieldId ]
                                    |> Event.simulate (Event.input value)
                                    |> Event.toResult
                    in
                    case formDelegationResult of
                        Ok msg ->
                            applyMsgWithLabel stepLabel Interaction (Just (ByFormField fieldId fieldName)) msg (ProgramTest state)

                        Err _ ->
                            case labelWrappedResult of
                                Ok msg ->
                                    applyMsgWithLabel stepLabel Interaction (Just (ByLabelText fieldName)) msg (ProgramTest state)

                                Err _ ->
                                    case idResult of
                                        Ok msg ->
                                            applyMsgWithLabel stepLabel Interaction (Just (ById fieldId)) msg (ProgramTest state)

                                        Err errMsg ->
                                            ProgramTest
                                                { state
                                                    | error =
                                                        Just
                                                            (stepLabel
                                                                ++ " failed: Could not find input.\n\nTried:\n"
                                                                ++ "  1. <form id=\""
                                                                ++ fieldId
                                                                ++ "\"> with delegated input event\n"
                                                                ++ "  2. <label> containing \""
                                                                ++ fieldName
                                                                ++ "\" wrapping an <input>\n"
                                                                ++ "  3. <input id=\""
                                                                ++ fieldId
                                                                ++ "\">\n\n"
                                                                ++ errMsg
                                                            )
                                                }



{-| Fill in a textarea with the given content. Finds the first `<textarea>`
element in the view (or within the current `within` scope) and simulates
an input event.

    |> PagesProgram.fillInTextarea "Hello, world!"

-}
fillInTextarea : String -> ProgramTest model msg -> ProgramTest model msg
fillInTextarea newContent (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state | error = Just "fillInTextarea: Cannot interact while BackendTask data is still resolving." }

                Ready ready ->
                    let
                        textareaQuery =
                            renderScopedView ready
                                |> Query.find [ Selector.tag "textarea" ]

                        eventResult =
                            textareaQuery
                                |> Event.simulate (Event.input newContent)
                                |> Event.toResult
                    in
                    case eventResult of
                        Ok msg ->
                            applyMsgWithLabel "fillInTextarea" Interaction (Just (ByTag "textarea")) msg (ProgramTest state)

                        Err errMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just ("fillInTextarea failed:\n\n" ++ errMsg)
                                }


{-| Simulate clicking a link with the given text and href.
-}
clickLink : String -> String -> ProgramTest model msg -> ProgramTest model msg
clickLink linkText href (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("clickLink \""
                                        ++ linkText
                                        ++ "\": Cannot interact while BackendTask data is still resolving."
                                    )
                        }

                Ready ready ->
                    let
                        query : Query.Single msg
                        query =
                            renderScopedView ready

                        linkSelectors : List Selector.Selector
                        linkSelectors =
                            [ Selector.tag "a"
                            , Selector.attribute (Html.Attributes.href href)
                            , Selector.containing [ Selector.text linkText ]
                            ]

                        -- Verify link exists in the view
                        linkExists : Expectation
                        linkExists =
                            query
                                |> Query.find linkSelectors
                                |> Query.has []
                    in
                    case getFailureMessage linkExists of
                        Just errMsg ->
                            let
                                sameTextLinkExists =
                                    query
                                        |> Query.find
                                            [ Selector.tag "a"
                                            , Selector.containing [ Selector.text linkText ]
                                            ]
                                        |> Query.has []
                            in
                            case getFailureMessage sameTextLinkExists of
                                Nothing ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just
                                                    ("clickLink \""
                                                        ++ linkText
                                                        ++ "\" failed: found link text, but no link with href \""
                                                        ++ href
                                                        ++ "\"\n\n"
                                                        ++ errMsg
                                                    )
                                        }

                                Just _ ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just
                                                    ("clickLink \""
                                                        ++ linkText
                                                        ++ "\" failed: link not found\n\n"
                                                        ++ errMsg
                                                    )
                                        }

                        Nothing ->
                            -- Link exists. Navigate using onNavigate if available.
                            case ready.onNavigate of
                                Just navigate ->
                                    applyMsgWithLabel
                                        ("clickLink \"" ++ linkText ++ "\"")
                                        Interaction
                                        (Just (ByTagAndText "a" linkText))
                                        (navigate href)
                                        (ProgramTest state)

                                Nothing ->
                                    -- No navigation handler (old API). Try event simulation.
                                    let
                                        linkQuery =
                                            query
                                                |> Query.find linkSelectors

                                        eventResult =
                                            linkQuery
                                                |> Event.simulate Event.click
                                                |> Event.toResult
                                    in
                                    case eventResult of
                                        Ok msg ->
                                            applyMsgWithLabel ("clickLink \"" ++ linkText ++ "\"") Interaction (Just (ByTagAndText "a" linkText)) msg (ProgramTest state)

                                        Err clickErr ->
                                            ProgramTest
                                                { state
                                                    | error =
                                                        Just
                                                            ("clickLink \""
                                                                ++ linkText
                                                                ++ "\" failed: no navigation handler or click handler found.\n"
                                                                ++ clickErr
                                                            )
                                                }


{-| Navigate directly to a URL path. In framework-driven tests, this triggers
the full Platform navigation cycle: `LinkClicked` -> `UrlChanged` ->
data loading -> re-render.

    TestApp.start "/" mockData
        |> PagesProgram.navigateTo "/counter"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 0" ]

-}
navigateTo : String -> ProgramTest model msg -> ProgramTest model msg
navigateTo path (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error = Just "navigateTo: Cannot navigate while BackendTask data is still resolving."
                        }

                Ready ready ->
                    case ready.onNavigate of
                        Just navigate ->
                            applyMsgWithLabel
                                ("navigateTo \"" ++ path ++ "\"")
                                Interaction
                                Nothing
                                (navigate path)
                                (ProgramTest state)

                        Nothing ->
                            ProgramTest
                                { state
                                    | error = Just "navigateTo: Navigation is only supported with startPlatform (framework-driven tests)."
                                }


{-| Assert on the current browser URL. Use with framework-driven tests
(`startPlatform`) where navigation is tracked by the Platform.

    TestApp.start "/hello" mockData
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/hello")

-}
ensureBrowserUrl : (String -> Expectation) -> ProgramTest model msg -> ProgramTest model msg
ensureBrowserUrl assertion (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state | error = Just "ensureBrowserUrl: Cannot check URL while data is resolving." }

                Ready ready ->
                    case ready.getBrowserUrl of
                        Just getUrl ->
                            let
                                currentUrl =
                                    getUrl ready.model

                                result =
                                    assertion currentUrl
                            in
                            case getFailureMessage result of
                                Just failMsg ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just ("ensureBrowserUrl failed:\n\n" ++ failMsg)
                                        }

                                Nothing ->
                                    ProgramTest state
                                        |> recordAssertionSnapshot ("ensureBrowserUrl " ++ currentUrl)

                        Nothing ->
                            ProgramTest
                                { state
                                    | error = Just "ensureBrowserUrl: URL tracking is only supported with startPlatform (framework-driven tests)."
                                }


{-| Submit a form with the given fields. In framework-driven tests, this
triggers the full action pipeline: the action BackendTask is resolved, and
the result is rendered as `actionData` in the view.

    TestApp.start "/feedback" mockData
        |> PagesProgram.submitForm
            { formId = "feedback-form"
            , fields = [ ( "message", "Hello!" ) ]
            }
        |> PagesProgram.ensureViewHas [ Selector.text "You said: Hello!" ]

-}
submitForm :
    { formId : String, fields : List ( String, String ) }
    -> ProgramTest model msg
    -> ProgramTest model msg
submitForm formInfo =
    submitFormTo "" formInfo


{-| Submit a form to a specific action URL. Use this for forms that POST
to a different route (e.g., a logout form that posts to `/logout`).

    |> PagesProgram.submitFormTo "/logout"
        { formId = "logout-form", fields = [] }

For forms that submit to the current route, use `submitForm` instead.

-}
submitFormTo :
    String
    -> { formId : String, fields : List ( String, String ) }
    -> ProgramTest model msg
    -> ProgramTest model msg
submitFormTo action formInfo (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state | error = Just "submitForm: Cannot submit while data is resolving." }

                Ready ready ->
                    case ready.onFormSubmit of
                        Just handler ->
                            applyMsgWithLabel
                                ("submitForm \"" ++ formInfo.formId ++ "\"")
                                Interaction
                                (if formInfo.formId /= "" then
                                    Just (ById formInfo.formId)
                                 else
                                    Nothing
                                )
                                (handler { formId = formInfo.formId, action = action, fields = formInfo.fields, useFetcher = False })
                                (ProgramTest state)

                        Nothing ->
                            ProgramTest
                                { state
                                    | error = Just "submitForm: Form submission is only supported with startPlatform (framework-driven tests)."
                                }


{-| Submit a fetcher form by its form ID. Unlike `submitForm`, this uses the
fetcher submission path (`useFetcher = True`), which means the submission
appears in `app.concurrentSubmissions` and enables optimistic UI.

Use this for forms rendered with `Pages.Form.withConcurrent`, especially
those whose buttons have no text content (like toggle checkboxes or delete
icons).

    TestApp.start "/" setup
        |> PagesProgram.simulateCustom "getTodos" todosResponse
        |> PagesProgram.submitFetcher "toggle-todo-1"
        |> PagesProgram.ensureViewHas [ Selector.class "completed" ]

-}
submitFetcher :
    String
    -> ProgramTest model msg
    -> ProgramTest model msg
submitFetcher formId (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state | error = Just "submitFetcher: Cannot submit while data is resolving." }

                Ready ready ->
                    case ready.onFormSubmit of
                        Just handler ->
                            let
                                fields =
                                    ready.getFormFields
                                        |> Maybe.map (\getFields -> getFields ready.model)
                                        |> Maybe.withDefault []
                            in
                            applyMsgWithLabel
                                ("submitFetcher \"" ++ formId ++ "\"")
                                Interaction
                                (if formId /= "" then
                                    Just (ById formId)

                                 else
                                    Nothing
                                )
                                (handler { formId = formId, action = "", fields = fields, useFetcher = True })
                                (ProgramTest state)

                        Nothing ->
                            ProgramTest
                                { state
                                    | error = Just "submitFetcher: Form submission is only supported with startPlatform (framework-driven tests)."
                                }


{-| Simulate checking or unchecking a checkbox. Finds the input by its `id`
attribute and simulates a `change` event with the given checked state.

    PagesProgram.start config
        |> PagesProgram.check "agree" True
        |> PagesProgram.ensureViewHas [ Selector.text "Terms accepted" ]

-}
check : String -> Bool -> ProgramTest model msg -> ProgramTest model msg
check fieldId isChecked (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("check \""
                                        ++ fieldId
                                        ++ "\": Cannot interact while BackendTask data is still resolving."
                                    )
                        }

                Ready ready ->
                    let
                        query : Query.Single msg
                        query =
                            renderScopedView ready

                        inputQuery : Query.Single msg
                        inputQuery =
                            query
                                |> Query.find [ Selector.id fieldId ]

                        eventResult : Result String msg
                        eventResult =
                            inputQuery
                                |> Event.simulate (Event.check isChecked)
                                |> Event.toResult
                    in
                    case eventResult of
                        Ok msg ->
                            applyMsgWithLabel
                                ("check \""
                                    ++ fieldId
                                    ++ "\" "
                                    ++ (if isChecked then
                                            "True"

                                        else
                                            "False"
                                       )
                                )
                                Interaction
                                (Just (ById fieldId))
                                msg
                                (ProgramTest state)

                        Err errMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("check \""
                                                ++ fieldId
                                                ++ "\" failed:\n\n"
                                                ++ errMsg
                                            )
                                }



-- EFFECT RESOLUTION


{-| Resolve a pending BackendTask effect using the full `Test.BackendTask` API.
When `init` or `update` returns a BackendTask effect, use this to simulate the
external dependency and feed the result back through `update`.

    import Test.BackendTask as BackendTaskTest

    PagesProgram.start fetchConfig
        |> PagesProgram.clickButton "Fetch"
        |> PagesProgram.resolveEffect
            (BackendTaskTest.simulateHttpGet
                "https://api.example.com/data"
                (Encode.list Encode.string [ "a", "b" ])
            )
        |> PagesProgram.ensureViewHas [ Selector.text "a" ]

-}
resolveEffect :
    (BackendTaskTest.BackendTaskTest msg -> BackendTaskTest.BackendTaskTest msg)
    -> ProgramTest model msg
    -> ProgramTest model msg
resolveEffect simulate (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just "resolveEffect: Cannot resolve effects while data BackendTask is still resolving."
                        }

                Ready ready ->
                    case ready.pendingEffects of
                        [] ->
                            ProgramTest
                                { state
                                    | error =
                                        Just "resolveEffect: No pending BackendTask effects to resolve."
                                }

                        bt :: rest ->
                            let
                                testResult : Result String msg
                                testResult =
                                    bt
                                        |> BackendTaskTest.fromBackendTask
                                        |> simulate
                                        |> BackendTaskTest.toResult
                            in
                            case testResult of
                                Ok msg ->
                                    let
                                        updateResult =
                                            ready.update msg ready.model
                                    in
                                    case updateResult.pendingPhase of
                                        Just pendingPhase ->
                                            ProgramTest
                                                { state
                                                    | phase = pendingPhase
                                                    , pendingFetcherEffects = state.pendingFetcherEffects ++ updateResult.fetcherResolvers
                                                    , lastReadyModel = Just updateResult.model
                                                    , snapshots =
                                                        state.snapshots
                                                            ++ [ makeSnapshot "resolveEffect" EffectResolution Nothing { ready | model = updateResult.model } state.modelToString state.fetcherExtractor state.networkLog ]
                                                }

                                        Nothing ->
                                            let
                                                newReady =
                                                    { ready
                                                        | model = updateResult.model
                                                        , pendingEffects = rest ++ updateResult.effects
                                                    }

                                                -- Mark all pending entries as stubbed
                                                updatedLog =
                                                    state.networkLog
                                                        |> List.map
                                                            (\entry ->
                                                                if entry.status == Pending then
                                                                    { entry | status = Stubbed, stepIndex = List.length state.snapshots }

                                                                else
                                                                    entry
                                                            )
                                            in
                                            ProgramTest
                                                { state
                                                    | phase = Ready newReady
                                                    , pendingFetcherEffects = state.pendingFetcherEffects ++ updateResult.fetcherResolvers
                                                    , snapshots =
                                                        state.snapshots
                                                            ++ [ makeSnapshot "resolveEffect" EffectResolution Nothing newReady state.modelToString state.fetcherExtractor updatedLog ]
                                                    , networkLog = updatedLog
                                                }

                                Err errMsg ->
                                    ProgramTest
                                        { state
                                            | error = Just ("resolveEffect failed:\n\n" ++ errMsg)
                                        }



-- VIEW ASSERTIONS


{-| Assert that the rendered view contains elements matching all the given
selectors. This is a chainable assertion -- it returns `ProgramTest` for
continued testing.

    test
        |> PagesProgram.ensureViewHas [ Selector.text "Welcome" ]
        |> PagesProgram.ensureViewHas [ Selector.id "main-content" ]

-}
ensureViewHas : List Selector.Selector -> ProgramTest model msg -> ProgramTest model msg
ensureViewHas selectors (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving (Resolver r) ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("ensureViewHas: Cannot check view while BackendTask data is still resolving. "
                                        ++ "Provide simulated responses first.\n\n"
                                        ++ r.pendingDescription
                                    )
                        }

                Ready ready ->
                    case ready.getModelError ready.model of
                        Just pendingError ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("ensureViewHas: " ++ pendingError)
                                }

                        Nothing ->
                            let
                                result : Expectation
                                result =
                                    renderScopedView ready |> Query.has selectors

                            in
                            case getFailureMessage result of
                                Just failMsg ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just
                                                    ("ensureViewHas failed:\n\n"
                                                        ++ failMsg
                                                    )
                                        }

                                Nothing ->
                                    ProgramTest state
                                        |> recordAssertionSnapshot ("ensureViewHas " ++ selectorLabel selectors)


{-| Assert that the rendered view does NOT contain elements matching the given
selectors. Chainable.
-}
ensureViewHasNot : List Selector.Selector -> ProgramTest model msg -> ProgramTest model msg
ensureViewHasNot selectors (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest { state | error = Just "ensureViewHasNot: Cannot check view while data is resolving." }

                Ready ready ->
                    case ready.getModelError ready.model of
                        Just pendingError ->
                            ProgramTest { state | error = Just ("ensureViewHasNot: " ++ pendingError) }

                        Nothing ->
                            let
                                result : Expectation
                                result =
                                    renderScopedView ready |> Query.hasNot selectors
                            in
                            case getFailureMessage result of
                                Just failMsg ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just
                                                    ("ensureViewHasNot failed:\n\n"
                                                        ++ failMsg
                                                    )
                                        }

                                Nothing ->
                                    ProgramTest state
                                        |> recordAssertionSnapshot ("ensureViewHasNot " ++ selectorLabel selectors)


{-| Assert on the rendered view using a custom assertion function.

    test
        |> PagesProgram.ensureView
            (\query ->
                query
                    |> Query.find [ Selector.tag "h1" ]
                    |> Query.has [ Selector.text "Title" ]
            )

-}
ensureView : (Query.Single msg -> Expectation) -> ProgramTest model msg -> ProgramTest model msg
ensureView assertion (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest { state | error = Just "ensureView: Cannot check view while data is resolving." }

                Ready ready ->
                    case ready.getModelError ready.model of
                        Just pendingError ->
                            ProgramTest { state | error = Just ("ensureView: " ++ pendingError) }

                        Nothing ->
                            let
                                result : Expectation
                                result =
                                    assertion (renderScopedView ready)
                            in
                            case getFailureMessage result of
                                Just failMsg ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just
                                                    ("ensureView failed:\n\n"
                                                        ++ failMsg
                                                    )
                                        }

                                Nothing ->
                                    ProgramTest state
                                        |> recordAssertionSnapshot "ensureView"



{-| Like `ensureViewHas`, but returns an `Expectation` (terminal -- ends
the pipeline). Use for final view assertions.

    myTest
        |> PagesProgram.expectViewHas [ Selector.text "Done!" ]

-}
expectViewHas : List Selector.Selector -> ProgramTest model msg -> Expectation
expectViewHas selectors (ProgramTest state) =
    case state.error of
        Just errMsg ->
            Expect.fail errMsg

        Nothing ->
            case state.phase of
                Resolving _ ->
                    Expect.fail "expectViewHas: Cannot check view while data is resolving."

                Ready ready ->
                    renderScopedView ready |> Query.has selectors


{-| Like `ensureViewHasNot`, but returns an `Expectation` (terminal).
-}
expectViewHasNot : List Selector.Selector -> ProgramTest model msg -> Expectation
expectViewHasNot selectors (ProgramTest state) =
    case state.error of
        Just errMsg ->
            Expect.fail errMsg

        Nothing ->
            case state.phase of
                Resolving _ ->
                    Expect.fail "expectViewHasNot: Cannot check view while data is resolving."

                Ready ready ->
                    renderScopedView ready |> Query.hasNot selectors


{-| Like `ensureView`, but returns an `Expectation` (terminal).
Gives full access to the `Query.Single` for custom assertions.

    myTest
        |> PagesProgram.expectView
            (Query.find [ Selector.id "main" ]
                >> Query.has [ Selector.tag "h1" ]
            )

-}
expectView : (Query.Single msg -> Expectation) -> ProgramTest model msg -> Expectation
expectView assertion (ProgramTest state) =
    case state.error of
        Just errMsg ->
            Expect.fail errMsg

        Nothing ->
            case state.phase of
                Resolving _ ->
                    Expect.fail "expectView: Cannot check view while data is resolving."

                Ready ready ->
                    assertion (renderScopedView ready)


{-| Scope interactions and assertions to a specific part of the DOM.
Like elm-program-test's `within`, the first argument narrows the query
and the second is the interaction to perform within that scope.

    myTest
        |> PagesProgram.within
            (Query.find [ Selector.id "sidebar" ])
            (PagesProgram.clickButton "Submit")
        |> PagesProgram.done

The scope is reset after the function returns.

-}
within : (Query.Single msg -> Query.Single msg) -> (ProgramTest model msg -> ProgramTest model msg) -> ProgramTest model msg -> ProgramTest model msg
within scopeFn action (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest state

                Ready ready ->
                    let
                        -- Apply the new scope on top of any existing scope
                        scopedReady =
                            { ready | viewScope = ready.viewScope >> scopeFn }

                        scopedState =
                            { state | phase = Ready scopedReady }

                        -- Run the action with the scoped view
                        (ProgramTest resultState) =
                            action (ProgramTest scopedState)
                    in
                    -- Restore the original viewScope but keep everything else
                    ProgramTest
                        { resultState
                            | phase =
                                case resultState.phase of
                                    Ready resultReady ->
                                        Ready { resultReady | viewScope = ready.viewScope }

                                    other ->
                                        other
                        }


{-| Render the view and apply the current viewScope for querying.
-}
renderScopedView : ReadyState model msg -> Query.Single msg
renderScopedView ready =
    let
        viewHtml =
            ready.getView ready.model
    in
    Query.fromHtml (Html.div [] viewHtml.body)
        |> ready.viewScope


{-| Inspect the model directly. Useful for debugging or asserting on
internal state that isn't visible in the view.

    myTest
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.expectModel
            (\model -> model.count |> Expect.equal 1)

-}
expectModel : (model -> Expectation) -> ProgramTest model msg -> Expectation
expectModel assertion (ProgramTest state) =
    case state.error of
        Just errMsg ->
            Expect.fail errMsg

        Nothing ->
            case state.phase of
                Resolving _ ->
                    Expect.fail "expectModel: Cannot inspect model while BackendTask is resolving."

                Ready ready ->
                    assertion ready.model


-- TERMINAL


{-| Finalize the test. Fails if any earlier assertion failed, or if there are
unresolved pending BackendTask effects.
-}
done : ProgramTest model msg -> Expectation
done (ProgramTest state) =
    case state.error of
        Just msg ->
            Expect.fail msg

        Nothing ->
            case state.phase of
                Resolving (Resolver r) ->
                    Expect.fail
                        ("Test ended while BackendTask data is still resolving.\n\n"
                            ++ r.pendingDescription
                        )

                Ready ready ->
                    if List.isEmpty ready.pendingEffects then
                        Expect.pass

                    else
                        let
                            descriptions =
                                describeEffects ready.pendingEffects

                            descriptionText =
                                if List.isEmpty descriptions then
                                    ""

                                else
                                    "\n\nPending:\n"
                                        ++ (descriptions
                                                |> List.map (\d -> "  - " ++ d)
                                                |> String.join "\n"
                                           )
                        in
                        Expect.fail
                            ("There are "
                                ++ String.fromInt (List.length ready.pendingEffects)
                                ++ " pending BackendTask effect(s) that must be resolved before ending the test."
                                ++ descriptionText
                            )



-- SNAPSHOTS


{-| Extract snapshots from a test pipeline. Each step (start, clickButton,
fillIn, resolveEffect, simulateHttp) records a snapshot of the rendered view.

If the pipeline encountered an error, a final snapshot with the error is
appended so it's visible in the test stepper.

Use this with the visual test runner to step through test execution in the
browser.

    myTest
        |> PagesProgram.toSnapshots
        |> List.map .label
        -- [ "start", "clickButton \"+1\"", "clickButton \"+1\"" ]

-}
toSnapshots : ProgramTest model msg -> List Snapshot
toSnapshots (ProgramTest state) =
    case state.error of
        Just errorMsg ->
            state.snapshots
                ++ [ { label = "ERROR"
                     , title = "Error"
                     , body = [ Html.text errorMsg ]
                     , rerender = \() -> { title = "Error", body = [ Html.text errorMsg ] }
                     , hasPendingEffects = False
                     , modelState = Nothing
                     , stepKind = Error
                     , browserUrl = Nothing
                     , errorMessage = Just errorMsg
                     , pendingEffects = []
                     , networkLog = state.networkLog
                     , targetElement = Nothing
                     , fetcherLog = []
                     }
                   ]

        Nothing ->
            state.snapshots


{-| Enable model state inspection in snapshots. Pass `Debug.toString` (or any
`model -> String` function) and each snapshot will include the model state.

Since published packages cannot use `Debug.toString` directly, this must be
called from your test code:

    myTest
        |> PagesProgram.withModelToString Debug.toString
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.toSnapshots

-}
withModelToString : (model -> String) -> ProgramTest model msg -> ProgramTest model msg
withModelToString fn (ProgramTest state) =
    let
        updatedSnapshots =
            state.snapshots
                |> List.map
                    (\snapshot ->
                        case state.phase of
                            Ready ready ->
                                { snapshot | modelState = Just (fn ready.model) }

                            _ ->
                                snapshot
                    )
    in
    ProgramTest
        { state
            | modelToString = Just fn
            , snapshots = updatedSnapshots
        }



-- INTERNAL HELPERS


{-| Try advancing a resolver with a simulation. Returns Ok ProgramTest
on success, Err on AdvanceError.
-}
advanceResolver : Maybe model -> Simulation -> State model msg -> Resolver model msg -> Result String (ProgramTest model msg)
advanceResolver maybeModel sim state (Resolver resolver) =
    let
        ( simLabel, simMethod, simUrl ) =
            case sim of
                SimHttpGet url _ ->
                    ( "simulateHttpGet " ++ url, "GET", url )

                SimHttpPost url _ ->
                    ( "simulateHttpPost " ++ url, "POST", url )

                SimHttpError method url errorString ->
                    ( "simulateHttpError " ++ method ++ " " ++ url ++ " " ++ errorString, method, url )

                SimCustom portName _ ->
                    ( "simulateCustom " ++ portName, "GET", "elm-pages-internal://port" )

        stepIdx =
            List.length state.snapshots

        networkEntry =
            { method = simMethod
            , url = simUrl
            , status = Stubbed
            , stepIndex = stepIdx
            }

        updatedLog =
            state.networkLog ++ [ networkEntry ]
    in
    case resolver.advance maybeModel sim of
        Advanced newPhase ->
            let
                snapshot =
                    case newPhase of
                        Ready ready ->
                            [ makeSnapshot simLabel EffectResolution Nothing ready state.modelToString state.fetcherExtractor updatedLog ]

                        Resolving _ ->
                            []
            in
            Ok
                (ProgramTest
                    { state
                        | phase = newPhase
                        , snapshots = state.snapshots ++ snapshot
                        , networkLog = updatedLog
                    }
                )

        AdvanceError errMsg ->
            Err errMsg


advanceResolverOrError : Maybe model -> Simulation -> State model msg -> Resolver model msg -> ProgramTest model msg
advanceResolverOrError maybeModel sim state resolver =
    case advanceResolver maybeModel sim state resolver of
        Ok programTest ->
            programTest

        Err errMsg ->
            ProgramTest { state | error = Just errMsg }


applySimulation : Simulation -> ProgramTest model msg -> ProgramTest model msg
applySimulation sim (ProgramTest state) =
    case state.error of
        Just err ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving ((Resolver resolverRecord) as resolver) ->
                    -- When pending fetcher effects exist, try them first. Fetchers
                    -- represent user interactions that should resolve before background
                    -- data reloads. This prevents a stale data reload resolver from
                    -- consuming a response meant for a fetcher mutation (which would
                    -- happen when mutation and data responses share the same JSON shape).
                    case ( state.pendingFetcherEffects, state.lastReadyModel ) of
                        ( ((Resolver _) as fetcherResolver) :: restFetchers, Just currentModel ) ->
                            case advanceResolver (Just currentModel) sim state fetcherResolver of
                                Ok (ProgramTest newState) ->
                                    -- Fetcher advanced. The stale data reload is superseded.
                                    ProgramTest { newState | pendingFetcherEffects = restFetchers }

                                Err _ ->
                                    -- Fetcher didn't accept this sim. Try the main resolver.
                                    advanceResolverOrError Nothing sim state resolver

                        _ ->
                            advanceResolverOrError Nothing sim state resolver

                Ready ready ->
                    -- No navigation/action HTTP pending. Check for pending fetcher effects.
                    case state.pendingFetcherEffects of
                        ((Resolver _) as fetcherResolver) :: restFetchers ->
                            case advanceResolver (Just ready.model) sim state fetcherResolver of
                                Ok (ProgramTest newState) ->
                                    ProgramTest
                                        { newState
                                            | pendingFetcherEffects = restFetchers
                                            , lastReadyModel =
                                                case newState.phase of
                                                    Resolving _ ->
                                                        Just ready.model

                                                    Ready _ ->
                                                        state.lastReadyModel
                                        }

                                Err errMsg ->
                                    ProgramTest { state | error = Just ("Fetcher effect resolution failed:\n\n" ++ errMsg) }

                        [] ->
                            ProgramTest
                                { state
                                    | error =
                                        Just "No pending BackendTask to simulate. The page is already initialized."
                                }


{-| Like applySimulation, but targets a resolver whose pendingUrls contains
the given URL. Searches the phase resolver and pendingFetcherEffects.
-}
applySimulationToUrl : String -> Simulation -> ProgramTest model msg -> ProgramTest model msg
applySimulationToUrl targetUrl sim (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving ((Resolver resolverRecord) as resolver) ->
                    if List.member targetUrl resolverRecord.pendingUrls then
                        -- Phase resolver matches the URL
                        advanceResolverOrError Nothing sim state resolver

                    else
                        -- Phase resolver doesn't match. Search pendingFetcherEffects.
                        case findResolverByUrl targetUrl state.pendingFetcherEffects of
                            Just ( matchedResolver, restFetchers ) ->
                                case state.lastReadyModel of
                                    Just currentModel ->
                                        case advanceResolver (Just currentModel) sim state matchedResolver of
                                            Ok (ProgramTest newState) ->
                                                ProgramTest { newState | pendingFetcherEffects = restFetchers }

                                            Err errMsg ->
                                                ProgramTest { state | error = Just errMsg }

                                    Nothing ->
                                        ProgramTest { state | error = Just ("simulateHttpTo: No current model available for fetcher resolver matching " ++ targetUrl) }

                            Nothing ->
                                ProgramTest
                                    { state
                                        | error =
                                            Just
                                                ("No pending resolver found for URL: "
                                                    ++ targetUrl
                                                    ++ "\n\nPhase resolver pending: "
                                                    ++ resolverRecord.pendingDescription
                                                    ++ "\n\nPending fetcher effects: "
                                                    ++ String.fromInt (List.length state.pendingFetcherEffects)
                                                )
                                    }

                Ready ready ->
                    case findResolverByUrl targetUrl state.pendingFetcherEffects of
                        Just ( matchedResolver, restFetchers ) ->
                            case advanceResolver (Just ready.model) sim state matchedResolver of
                                Ok (ProgramTest newState) ->
                                    ProgramTest
                                        { newState
                                            | pendingFetcherEffects = restFetchers
                                            , lastReadyModel =
                                                case newState.phase of
                                                    Resolving _ ->
                                                        Just ready.model

                                                    Ready _ ->
                                                        state.lastReadyModel
                                        }

                                Err errMsg ->
                                    ProgramTest { state | error = Just ("Fetcher effect resolution failed:\n\n" ++ errMsg) }

                        Nothing ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("No pending resolver found for URL: "
                                                ++ targetUrl
                                                ++ "\n\nPending fetcher effects: "
                                                ++ String.fromInt (List.length state.pendingFetcherEffects)
                                            )
                                }


{-| Find the first resolver in the list whose pendingUrls contains the target URL.
Returns the matching resolver and the remaining list (with the match removed).
-}
findResolverByUrl : String -> List (Resolver model msg) -> Maybe ( Resolver model msg, List (Resolver model msg) )
findResolverByUrl targetUrl resolvers =
    findResolverByUrlHelp targetUrl [] resolvers


findResolverByUrlHelp : String -> List (Resolver model msg) -> List (Resolver model msg) -> Maybe ( Resolver model msg, List (Resolver model msg) )
findResolverByUrlHelp targetUrl before remaining =
    case remaining of
        [] ->
            Nothing

        ((Resolver r) as resolver) :: rest ->
            if List.member targetUrl r.pendingUrls then
                Just ( resolver, List.reverse before ++ rest )

            else
                findResolverByUrlHelp targetUrl (resolver :: before) rest


{-| Record a snapshot for an assertion step (like Cypress's command log).
Assertions show up in the timeline so you can see what was checked.
-}
recordAssertionSnapshot : String -> ProgramTest model msg -> ProgramTest model msg
recordAssertionSnapshot label (ProgramTest state) =
    case state.phase of
        Ready ready ->
            ProgramTest
                { state
                    | snapshots =
                        state.snapshots
                            ++ [ makeSnapshot label Assertion Nothing ready state.modelToString state.fetcherExtractor state.networkLog ]
                }

        _ ->
            ProgramTest state


selectorLabel : List Selector.Selector -> String
selectorLabel selectors =
    "[" ++ String.fromInt (List.length selectors) ++ " selector(s)]"


{-| Apply a message through update, record a snapshot, and re-render.
-}
applyMsgWithLabel : String -> StepKind -> Maybe TargetSelector -> msg -> ProgramTest model msg -> ProgramTest model msg
applyMsgWithLabel label kind target msg (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error = Just "Cannot apply message while BackendTask is resolving."
                        }

                Ready ready ->
                    let
                        updateResult =
                            ready.update msg ready.model
                    in
                    case updateResult.pendingPhase of
                        Just pendingPhase ->
                            -- Update triggered a BackendTask that needs HTTP simulation.
                            -- Transition to the pending phase (Resolving) so the user
                            -- can provide responses via simulateHttpPost etc.
                            -- Fetcher effects survive the transition via state.
                            let
                                newReady =
                                    { ready | model = updateResult.model }
                            in
                            ProgramTest
                                { state
                                    | phase = pendingPhase
                                    , pendingFetcherEffects = state.pendingFetcherEffects ++ updateResult.fetcherResolvers
                                    , lastReadyModel = Just updateResult.model
                                    , snapshots =
                                        state.snapshots
                                            ++ [ makeSnapshot label kind target newReady state.modelToString state.fetcherExtractor state.networkLog ]
                                }

                        Nothing ->
                            let
                                newReady =
                                    { ready
                                        | model = updateResult.model
                                        , pendingEffects = ready.pendingEffects ++ updateResult.effects
                                    }

                                stepIdx =
                                    List.length state.snapshots

                                newPendingEntries =
                                    describeEffects updateResult.effects
                                        |> List.filterMap
                                            (\desc ->
                                                parseEffectToNetworkEntry stepIdx desc
                                            )

                                updatedLog =
                                    state.networkLog ++ newPendingEntries
                            in
                            ProgramTest
                                { state
                                    | phase = Ready newReady
                                    , pendingFetcherEffects = state.pendingFetcherEffects ++ updateResult.fetcherResolvers
                                    , snapshots =
                                        state.snapshots
                                            ++ [ makeSnapshot label kind target newReady state.modelToString state.fetcherExtractor updatedLog ]
                                    , networkLog = updatedLog
                                }


makeSnapshot : String -> StepKind -> Maybe TargetSelector -> ReadyState model msg -> Maybe (model -> String) -> Maybe (model -> List FetcherEntry) -> List NetworkEntry -> Snapshot
makeSnapshot label kind target ready modelToString fetcherExtractor currentNetworkLog =
    let
        viewResult =
            ready.getView ready.model
    in
    { label = label
    , title = viewResult.title
    , body = (mapViewToSnapshot viewResult).body
    , rerender = \() -> mapViewToSnapshot (ready.getView ready.model)
    , hasPendingEffects = not (List.isEmpty ready.pendingEffects)
    , modelState = Maybe.map (\fn -> fn ready.model) modelToString
    , stepKind = kind
    , browserUrl = ready.getBrowserUrl |> Maybe.map (\getUrl -> getUrl ready.model)
    , errorMessage = Nothing
    , pendingEffects = describeEffects ready.pendingEffects
    , networkLog = currentNetworkLog
    , targetElement = target
    , fetcherLog = fetcherExtractor |> Maybe.map (\fn -> fn ready.model) |> Maybe.withDefault []
    }


{-| Convert pending BackendTask effects into human-readable descriptions.
Each effect is auto-resolved as far as possible, then we extract what's still
pending (HTTP URLs, commands, etc.).
-}
describeEffects : List (BackendTask FatalError msg) -> List String
describeEffects effects =
    effects
        |> List.concatMap
            (\bt ->
                case BackendTaskTest.fromBackendTask bt of
                    BackendTaskTest.Running runningState ->
                        if List.isEmpty runningState.pendingRequests then
                            [ "BackendTask (pending)" ]

                        else
                            runningState.pendingRequests
                                |> List.map describeHttpRequest

                    BackendTaskTest.Done _ ->
                        []

                    BackendTaskTest.TestError errMsg ->
                        [ "Error: " ++ errMsg ]
            )


describeHttpRequest : StaticHttpRequest.Request -> String
describeHttpRequest req =
    req.method ++ " " ++ req.url


{-| Parse an effect description string into a NetworkEntry if it's an HTTP request.
-}
parseEffectToNetworkEntry : Int -> String -> Maybe NetworkEntry
parseEffectToNetworkEntry stepIndex desc =
    case String.split " " desc of
        method :: rest ->
            if List.member method [ "GET", "POST", "PUT", "DELETE", "PATCH" ] then
                Just
                    { method = method
                    , url = String.join " " rest
                    , status = Pending
                    , stepIndex = stepIndex
                    }

            else
                Nothing

        _ ->
            Nothing


mapViewToSnapshot : { title : String, body : List (Html msg) } -> { title : String, body : List (Html Never) }
mapViewToSnapshot v =
    -- We store body as Html Never for the snapshot viewer (non-interactive).
    -- This is safe because the viewer maps all events to NoOp anyway.
    { title = v.title, body = unsafeCoerceHtmlList v.body }


unsafeCoerceHtmlList : List (Html a) -> List (Html b)
unsafeCoerceHtmlList =
    -- elm-explorations/test uses the same trick internally.
    -- Html is a virtual-dom node; the msg type param is phantom.
    List.map (Html.map (\_ -> crashNever ()))


crashNever : () -> a
crashNever () =
    crashNever ()


{-| Build a data-phase resolver that hides the `data` type parameter.
When the BackendTask resolves, calls `initFn` to get the model and transitions
to `Ready`. When it can't resolve yet, returns a new `Resolving` with updated
BackendTask state.
-}
resolveDataPhase :
    BackendTaskTest.BackendTaskTest data
    -> (data -> ( model, List (BackendTask FatalError msg) ))
    -> (data -> model -> { title : String, body : List (Html msg) })
    -> (msg -> model -> ( model, List (BackendTask FatalError msg) ))
    -> Phase model msg
resolveDataPhase bt initFn viewFn updateFn =
    case bt of
        BackendTaskTest.Done doneState ->
            case doneState.result of
                Ok data ->
                    let
                        ( model, effects ) =
                            initFn data
                    in
                    Ready
                        { model = model
                        , getView = viewFn data
                        , update = \msg m -> let ( m2, effs ) = updateFn msg m in { model = m2, effects = effs, pendingPhase = Nothing, fetcherResolvers = [] }
                        , pendingEffects = effects
                        , onNavigate = Nothing
                        , getBrowserUrl = Nothing
                        , onFormSubmit = Nothing
                        , getFormFields = Nothing
                        , viewScope = identity
                        , getModelError = \_ -> Nothing
                        }

                Err err ->
                    -- BackendTask completed with FatalError -- produce a clean error
                    let
                        (Pages.Internal.FatalError.FatalError errInfo) =
                            err
                    in
                    Resolving
                        (Resolver
                            { advance = \_ _ -> AdvanceError (errInfo.title ++ ": " ++ errInfo.body)
                            , pendingDescription =
                                "Data BackendTask failed with FatalError:\n\n"
                                    ++ errInfo.title
                                    ++ "\n"
                                    ++ errInfo.body
                            , pendingUrls = []
                            }
                        )

        BackendTaskTest.Running runningState ->
            Resolving
                (Resolver
                    { advance =
                        \_ sim ->
                            let
                                newBt : BackendTaskTest.BackendTaskTest data
                                newBt =
                                    case sim of
                                        SimHttpGet url resp ->
                                            BackendTaskTest.simulateHttpGet url resp bt

                                        SimHttpPost url resp ->
                                            BackendTaskTest.simulateHttpPost url resp bt

                                        SimHttpError method url errorString ->
                                            BackendTaskTest.simulateHttpError method url errorString bt

                                        SimCustom portName resp ->
                                            BackendTaskTest.simulateCustom portName resp bt
                            in
                            Advanced (resolveDataPhase newBt initFn viewFn updateFn)
                    , pendingDescription =
                        stillRunningDescription runningState.pendingRequests
                    , pendingUrls =
                        List.map .url runningState.pendingRequests
                    }
                )

        BackendTaskTest.TestError msg ->
            Resolving
                (Resolver
                    { advance = \_ _ -> AdvanceError msg
                    , pendingDescription = msg
                    , pendingUrls = []
                    }
                )


getFailureMessage : Expectation -> Maybe String
getFailureMessage expectation =
    case Test.Runner.getFailureReason expectation of
        Just reason ->
            let
                reasonDetail =
                    case reason.reason of
                        Test.Runner.Failure.Equality expected actual ->
                            "\n\nExpected:\n    " ++ expected ++ "\n\nActual:\n    " ++ actual

                        Test.Runner.Failure.Custom ->
                            ""

                        _ ->
                            ""

                base =
                    reason.description ++ reasonDetail
            in
            Just base

        Nothing ->
            Nothing


stillRunningDescription : List { a | url : String } -> String
stillRunningDescription pendingRequests =
    "Pending requests:\n\n"
        ++ (pendingRequests
                |> List.map (\req -> "    " ++ req.url)
                |> String.join "\n"
           )




-- PLATFORM HELPERS


{-| Result of resolving initial data. Either fully resolved (with encoded bytes
for FrozenViewsReady), pending HTTP (data BackendTask needs simulation), or
a fatal error.
-}
type InitialDataResult sharedData dataResponse
    = InitialDataResolved BackendTaskTest.VirtualFS Bytes.Bytes
    | InitialDataPending BackendTaskTest.VirtualFS sharedData (BackendTaskTest.BackendTaskTest dataResponse)
    | InitialDataError String


{-| Resolve shared data, route data, and encode as ResponseSketch bytes for
Platform.FrozenViewsReady. Returns InitialDataPending when route data has
pending HTTP that needs simulation.
-}
resolveInitialData config initialUrl initialPath virtualFs =
    let
        ( vfs1, sharedResult ) =
            BackendTaskTest.resolveWithVirtualFs virtualFs config.sharedData
    in
    case sharedResult of
        Err sharedErr ->
            InitialDataError ("Failed to resolve Shared.template.data: " ++ sharedErr)

        Ok resolvedSharedData ->
            let
                initialRoute =
                    config.urlToRoute initialUrl

                ( vfs2, handleResult ) =
                    BackendTaskTest.resolveWithVirtualFs vfs1 (config.handleRoute initialRoute)
            in
            case handleResult of
                Err handleErr ->
                    InitialDataError ("Failed to resolve handleRoute: " ++ handleErr)

                Ok (Just notFoundReason) ->
                    { reason = notFoundReason
                    , path = UrlPath.fromString initialPath
                    }
                        |> ResponseSketch.NotFound
                        |> encodeResponseWithPrefix config
                        |> (\bytes -> InitialDataResolved vfs2 bytes)

                Ok Nothing ->
                    let
                        ( vfs3, dataBt ) =
                            BackendTaskTest.resolveWithVirtualFsPartial vfs2
                                (config.data (platformTestRequest (Url.toString initialUrl) CookieJar.empty) initialRoute)
                    in
                    case dataBt of
                        BackendTaskTest.Done doneState ->
                            let
                                pageData =
                                    extractPageData config doneState.result
                            in
                            case pageData of
                                Just pd ->
                                    ResponseSketch.HotUpdate
                                        pd
                                        resolvedSharedData
                                        Nothing
                                        |> encodeResponseWithPrefix config
                                        |> (\bytes -> InitialDataResolved vfs3 bytes)

                                Nothing ->
                                    case doneState.result of
                                        Ok (ServerResponse serverResponse) ->
                                            case PageServerResponse.toRedirect serverResponse of
                                                Just { location } ->
                                                    ResponseSketch.Redirect location
                                                        |> encodeResponseWithPrefix config
                                                        |> (\bytes -> InitialDataResolved vfs3 bytes)

                                                Nothing ->
                                                    InitialDataError ("Unexpected server response with status " ++ String.fromInt serverResponse.statusCode)

                                        Err fatalErr ->
                                            -- Data BackendTask failed: show error page
                                            let
                                                errorPageData =
                                                    config.errorPageToData (config.internalError (fatalErrorToString fatalErr))
                                            in
                                            ResponseSketch.HotUpdate
                                                errorPageData
                                                resolvedSharedData
                                                Nothing
                                                |> encodeResponseWithPrefix config
                                                |> (\bytes -> InitialDataResolved vfs3 bytes)

                                        _ ->
                                            InitialDataError "Failed to resolve route data"

                        BackendTaskTest.Running runningState ->
                            InitialDataPending vfs3
                                resolvedSharedData
                                dataBt

                        BackendTaskTest.TestError errMsg ->
                            InitialDataError errMsg


{-| Recursively process Platform effects using the Test.BackendTask virtual FS.
File reads/writes are handled stateully -- action file writes update the
virtual FS and subsequent data resolution sees the updated files.
Returns (wrappedModel, trackedEffects) where wrappedModel contains both
the Platform model and the updated virtual FS.
-}
processEffectsWrapped config baseUrl makeReady makePlatformResolver wrappedModel effect maxDepth =
    if maxDepth <= 0 then
        ( wrappedModel, [], [] )

    else
        case effect of
            Platform.NoEffect ->
                ( wrappedModel, [], [] )

            Platform.ScrollToTop ->
                ( wrappedModel, [], [] )

            Platform.CancelRequest _ ->
                -- No-op: in the real Platform, this calls Http.cancel to abort
                -- in-flight data reloads. In tests, stale data reloads are handled
                -- by applySimulation's fetcher-first priority in the Resolving branch.
                ( wrappedModel, [], [] )

            Platform.RunCmd _ ->
                ( wrappedModel, [], [] )

            Platform.UserCmd _ ->
                ( wrappedModel, [], [] )

            Platform.BrowserLoadUrl _ ->
                ( wrappedModel, [], [] )

            Platform.BrowserPushUrl pushPath ->
                let
                    newUrl =
                        makeTestUrl baseUrl pushPath

                    ( newModel, newEffect ) =
                        platformUpdateClean config (Platform.UrlChanged newUrl) wrappedModel.platformModel
                in
                processEffectsWrapped config baseUrl makeReady makePlatformResolver
                    { wrappedModel | platformModel = newModel }
                    newEffect
                    (maxDepth - 1)

            Platform.BrowserReplaceUrl replacePath ->
                let
                    newUrl =
                        makeTestUrl baseUrl replacePath

                    ( newModel, newEffect ) =
                        platformUpdateClean config (Platform.UrlChanged newUrl) wrappedModel.platformModel
                in
                processEffectsWrapped config baseUrl makeReady makePlatformResolver
                    { wrappedModel | platformModel = newModel }
                    newEffect
                    (maxDepth - 1)

            Platform.FetchFrozenViews { path, query, body } ->
                let
                    -- Clean relative path prefix that Platform may produce
                    -- during redirect handling
                    cleanPath =
                        normalizePath path

                    pathWithQuery =
                        case query of
                            Just q ->
                                cleanPath ++ "?" ++ q

                            Nothing ->
                                cleanPath

                    fetchUrl =
                        makeTestUrl baseUrl pathWithQuery

                    route =
                        config.urlToRoute fetchUrl
                in
                case body of
                    Just formBody ->
                        -- Form submission: resolve action first, then handle result
                        let
                            actionRequest =
                                Internal.Request.Request
                                    { time = Time.millisToPosix 0
                                    , method = "POST"
                                    , body = Just formBody
                                    , rawUrl = baseUrl ++ path
                                    , rawHeaders =
                                        Dict.singleton "content-type"
                                            "application/x-www-form-urlencoded"
                                    , cookies = CookieJar.toDict wrappedModel.cookieJar
                                    }

                            ( vfsAfterAction, actionBt ) =
                                BackendTaskTest.resolveWithVirtualFsPartial
                                    wrappedModel.virtualFs
                                    (config.action actionRequest route)
                        in
                        case actionBt of
                            BackendTaskTest.Running runningState ->
                                -- Action has pending HTTP. Pause for simulation.
                                ( { wrappedModel
                                    | virtualFs = vfsAfterAction
                                    , pendingDataError =
                                        Just
                                            ("Route action has a pending BackendTask that needs a simulated response:\n\n"
                                                ++ stillRunningDescription runningState.pendingRequests
                                            )
                                    , pendingActionBody = Just { body = formBody, path = cleanPath }
                                  }
                                , []
                                , []
                                )

                            BackendTaskTest.TestError errMsg ->
                                ( { wrappedModel
                                    | virtualFs = vfsAfterAction
                                    , pendingDataError = Just ("Route action BackendTask error: " ++ errMsg)
                                  }
                                , []
                                , []
                                )

                            BackendTaskTest.Done doneState ->
                                case doneState.result of
                                    Ok (ServerResponse serverResponse) ->
                                        let
                                            updatedJar =
                                                wrappedModel.cookieJar
                                                    |> CookieJar.applySetCookieHeaders
                                                        (extractSetCookieHeaders (ServerResponse serverResponse))
                                        in
                                        case PageServerResponse.toRedirect serverResponse of
                                            Just { location } ->
                                                let
                                                    cleanLocation =
                                                        normalizePath location

                                                    encodedBytes =
                                                        ResponseSketch.Redirect cleanLocation
                                                            |> encodeResponseWithPrefix config

                                                    ( newModel, newEffect ) =
                                                        platformUpdateClean config
                                                            (Platform.FrozenViewsReady (Just encodedBytes))
                                                            wrappedModel.platformModel
                                                in
                                                processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                    { platformModel = newModel, virtualFs = vfsAfterAction, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                    newEffect
                                                    (maxDepth - 1)

                                            Nothing ->
                                                ( { wrappedModel | virtualFs = vfsAfterAction, cookieJar = updatedJar }, [], [] )

                                    Ok ((RenderPage renderMeta actionData) as renderResponse) ->
                                        let
                                            updatedJar =
                                                wrappedModel.cookieJar
                                                    |> CookieJar.applySetCookieHeaders
                                                        (extractSetCookieHeaders renderResponse)

                                            ( vfsAfterData, dataResult ) =
                                                BackendTaskTest.resolveWithVirtualFs
                                                    vfsAfterAction
                                                    (config.data (platformTestRequest (Url.toString fetchUrl) updatedJar) route)
                                        in
                                        case extractPageData config dataResult of
                                            Just pageData ->
                                                let
                                                    encodedBytes =
                                                        ResponseSketch.RenderPage pageData (Just actionData)
                                                            |> encodeResponseWithPrefix config

                                                    ( newModel, newEffect ) =
                                                        platformUpdateClean config
                                                            (Platform.FrozenViewsReady (Just encodedBytes))
                                                            wrappedModel.platformModel
                                                in
                                                processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                    { platformModel = newModel, virtualFs = vfsAfterData, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                    newEffect
                                                    (maxDepth - 1)

                                            Nothing ->
                                                ( { wrappedModel
                                                    | virtualFs = vfsAfterData
                                                    , cookieJar = updatedJar
                                                    , pendingDataError =
                                                        Just
                                                            ("Route data has a pending BackendTask that needs a simulated response after action completed:\n\n"
                                                                ++ (dataResult |> resultErrorToString)
                                                            )
                                                  }
                                                , []
                                                , []
                                                )

                                    Err fatalErr ->
                                        let
                                            (Pages.Internal.FatalError.FatalError errInfo) =
                                                fatalErr
                                        in
                                        ( { wrappedModel
                                            | virtualFs = vfsAfterAction
                                            , pendingDataError = Just ("Route action failed: " ++ errInfo.title ++ ": " ++ errInfo.body)
                                          }
                                        , []
                                        , []
                                        )

                                    _ ->
                                        ( { wrappedModel | virtualFs = vfsAfterAction }, [], [] )

                    Nothing ->
                        -- Navigation (no form body): resolve data only
                        let
                            ( vfsAfterData, dataResult ) =
                                BackendTaskTest.resolveWithVirtualFs
                                    wrappedModel.virtualFs
                                    (config.data (platformTestRequest (Url.toString fetchUrl) wrappedModel.cookieJar) route)
                        in
                        case dataResult of
                            Ok (ServerResponse serverResponse) ->
                                -- Data returned a redirect (e.g., session expired -> login)
                                let
                                    updatedJar =
                                        wrappedModel.cookieJar
                                            |> CookieJar.applySetCookieHeaders
                                                (extractSetCookieHeaders (ServerResponse serverResponse))
                                in
                                case PageServerResponse.toRedirect serverResponse of
                                    Just { location } ->
                                        let
                                            encodedBytes =
                                                ResponseSketch.Redirect location
                                                    |> encodeResponseWithPrefix config

                                            ( newModel, newEffect ) =
                                                platformUpdateClean config
                                                    (Platform.FrozenViewsReady (Just encodedBytes))
                                                    wrappedModel.platformModel
                                        in
                                        processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                            { platformModel = newModel, virtualFs = vfsAfterData, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                            newEffect
                                            (maxDepth - 1)

                                    Nothing ->
                                        ( { wrappedModel | virtualFs = vfsAfterData, cookieJar = updatedJar }, [], [] )

                            Err pendingError ->
                                ( { wrappedModel
                                    | virtualFs = vfsAfterData
                                    , pendingDataError = Just ("Route data has a pending BackendTask that needs a simulated response:\n\n" ++ pendingError)
                                    , pendingDataPath = Just pathWithQuery
                                  }
                                , []
                                , []
                                )

                            _ ->
                                case extractPageData config dataResult of
                                    Just pageData ->
                                        let
                                            -- Use HotUpdate for navigation data loads.
                                            -- RenderPage reuses the previous route's model which
                                            -- causes type mismatches after cross-route redirects.
                                            -- HotUpdate properly initializes the new route.
                                            encodedBytes =
                                                case wrappedModel.platformModel.pageData of
                                                    Ok prevData ->
                                                        ResponseSketch.HotUpdate pageData
                                                            prevData.sharedData
                                                            Nothing
                                                            |> encodeResponseWithPrefix config

                                                    Err _ ->
                                                        ResponseSketch.RenderPage pageData Nothing
                                                            |> encodeResponseWithPrefix config

                                            ( newModel, newEffect ) =
                                                platformUpdateClean config
                                                    (Platform.FrozenViewsReady (Just encodedBytes))
                                                    wrappedModel.platformModel

                                            -- Clear notFound after successful data load
                                            cleanedModel =
                                                { newModel | notFound = Nothing }
                                        in
                                        processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                            { platformModel = cleanedModel, virtualFs = vfsAfterData, cookieJar = wrappedModel.cookieJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                            newEffect
                                            (maxDepth - 1)

                                    Nothing ->
                                        ( { wrappedModel | virtualFs = vfsAfterData }, [], [] )

            Platform.Submit formData ->
                if formData.method == Form.Get then
                    let
                        newUrl =
                            makeTestUrl baseUrl
                                (formData.action
                                    ++ "?"
                                    ++ encodeFormFields formData.fields
                                )

                        ( newModel, newEffect ) =
                            platformUpdateClean config (Platform.UrlChanged newUrl) wrappedModel.platformModel
                    in
                    processEffectsWrapped config baseUrl makeReady makePlatformResolver
                        { wrappedModel | platformModel = newModel }
                        newEffect
                        (maxDepth - 1)

                else
                    -- POST form submission: resolve action (same as FetchFrozenViews with body)
                    let
                        submitPath =
                            formData.action
                                |> nonEmpty wrappedModel.platformModel.url.path

                        submitBody =
                            encodeFormFields formData.fields

                        submitUrl =
                            makeTestUrl baseUrl submitPath

                        submitRoute =
                            config.urlToRoute submitUrl

                        actionRequest =
                            Internal.Request.Request
                                { time = Time.millisToPosix 0
                                , method = "POST"
                                , body = Just submitBody
                                , rawUrl = baseUrl ++ submitPath
                                , rawHeaders =
                                    Dict.singleton "content-type"
                                        "application/x-www-form-urlencoded"
                                , cookies = CookieJar.toDict wrappedModel.cookieJar
                                }

                        ( vfsAfterAction, actionBt ) =
                            BackendTaskTest.resolveWithVirtualFsPartial
                                wrappedModel.virtualFs
                                (config.action actionRequest submitRoute)
                    in
                    case actionBt of
                        BackendTaskTest.Running runningState ->
                            ( { wrappedModel
                                | virtualFs = vfsAfterAction
                                , pendingDataError =
                                    Just
                                        ("Route action has a pending BackendTask that needs a simulated response:\n\n"
                                            ++ stillRunningDescription runningState.pendingRequests
                                        )
                                , pendingActionBody = Just { body = submitBody, path = submitPath }
                              }
                            , []
                            , []
                            )

                        BackendTaskTest.TestError errMsg ->
                            ( { wrappedModel
                                | virtualFs = vfsAfterAction
                                , pendingDataError = Just ("Route action BackendTask error: " ++ errMsg)
                              }
                            , []
                            , []
                            )

                        BackendTaskTest.Done doneState ->
                            case doneState.result of
                                Ok (ServerResponse serverResponse) ->
                                    let
                                        updatedJar =
                                            wrappedModel.cookieJar
                                                |> CookieJar.applySetCookieHeaders
                                                    (extractSetCookieHeaders (ServerResponse serverResponse))
                                    in
                                    case PageServerResponse.toRedirect serverResponse of
                                        Just { location } ->
                                            let
                                                cleanLocation =
                                                    if String.startsWith "./" location then
                                                        "/" ++ String.dropLeft 2 location

                                                    else
                                                        location

                                                encodedBytes =
                                                    ResponseSketch.Redirect cleanLocation
                                                        |> encodeResponseWithPrefix config

                                                ( newModel, newEffect ) =
                                                    platformUpdateClean config
                                                        (Platform.FrozenViewsReady (Just encodedBytes))
                                                        wrappedModel.platformModel
                                            in
                                            processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                { platformModel = newModel, virtualFs = vfsAfterAction, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                newEffect
                                                (maxDepth - 1)

                                        Nothing ->
                                            ( { wrappedModel | virtualFs = vfsAfterAction, cookieJar = updatedJar }, [], [] )

                                Ok ((RenderPage _ actionData) as renderResponse) ->
                                    let
                                        updatedJar =
                                            wrappedModel.cookieJar
                                                |> CookieJar.applySetCookieHeaders
                                                    (extractSetCookieHeaders renderResponse)

                                        ( vfsAfterData, dataResult ) =
                                            BackendTaskTest.resolveWithVirtualFs
                                                vfsAfterAction
                                                (config.data (platformTestRequest (Url.toString submitUrl) updatedJar) submitRoute)
                                    in
                                    case extractPageData config dataResult of
                                        Just pageData ->
                                            let
                                                encodedBytes =
                                                    ResponseSketch.RenderPage pageData (Just actionData)
                                                        |> encodeResponseWithPrefix config

                                                ( newModel, newEffect ) =
                                                    platformUpdateClean config
                                                        (Platform.FrozenViewsReady (Just encodedBytes))
                                                        wrappedModel.platformModel
                                            in
                                            processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                { platformModel = newModel, virtualFs = vfsAfterData, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                newEffect
                                                (maxDepth - 1)

                                        Nothing ->
                                            ( { wrappedModel
                                                | virtualFs = vfsAfterData
                                                , cookieJar = updatedJar
                                                , pendingDataError =
                                                    Just ("Route data has a pending BackendTask that needs a simulated response:\n\n" ++ resultErrorToString dataResult)
                                                , pendingDataPath = Just (normalizePath wrappedModel.platformModel.url.path)
                                              }
                                            , []
                                            , []
                                            )

                                Err fatalErr ->
                                    let
                                        (Pages.Internal.FatalError.FatalError errInfo) =
                                            fatalErr
                                    in
                                    ( { wrappedModel
                                        | virtualFs = vfsAfterAction
                                        , pendingDataError = Just ("Route action failed: " ++ errInfo.title ++ ": " ++ errInfo.body)
                                      }
                                    , []
                                    , []
                                    )

                                _ ->
                                    ( { wrappedModel | virtualFs = vfsAfterAction }, [], [] )

            Platform.SubmitFetcher fetcherKey transitionId formData ->
                let
                    -- Step 1: Dispatch FetcherStarted
                    ( modelAfterStarted, _ ) =
                        platformUpdateClean config
                            (Platform.FetcherStarted fetcherKey transitionId formData (Time.millisToPosix 0))
                            wrappedModel.platformModel

                    -- Step 2: Resolve the action
                    route =
                        config.urlToRoute (makeTestUrl baseUrl (formData.action |> nonEmpty wrappedModel.platformModel.url.path))

                    actionRequest =
                        Internal.Request.Request
                            { time = Time.millisToPosix 0
                            , method = "POST"
                            , body = Just (encodeFormFields formData.fields)
                            , rawUrl = baseUrl ++ (formData.action |> nonEmpty wrappedModel.platformModel.url.path)
                            , rawHeaders =
                                Dict.singleton "content-type"
                                    "application/x-www-form-urlencoded"
                            , cookies = CookieJar.toDict wrappedModel.cookieJar
                            }

                    actionBt =
                        config.action actionRequest route

                    ( vfsAfterAction, actionBtResult ) =
                        BackendTaskTest.resolveWithVirtualFsPartial
                            wrappedModel.virtualFs
                            actionBt
                in
                case actionBtResult of
                    BackendTaskTest.Running runningState ->
                        -- Fetcher action has pending HTTP. Don't block -- store
                        -- as a pending Resolver so the test can continue interacting
                        -- (enabling concurrent fetcher / optimistic UI testing).
                        let
                            ( _, pausedBt ) =
                                BackendTaskTest.resolveWithVirtualFsPartial
                                    wrappedModel.virtualFs
                                    actionBt

                            fetcherResolver =
                                Resolver
                                    { advance =
                                        \maybeCurrentModel sim ->
                                            let
                                                advancedBt =
                                                    applySimToBt sim pausedBt

                                                fetcherCompleteResult =
                                                    BackendTaskTest.toResult advancedBt
                                            in
                                            case fetcherCompleteResult of
                                                Ok actionResult ->
                                                    let
                                                        -- Use the current model if available, otherwise
                                                        -- fall back to the click-time model.
                                                        effectiveModel =
                                                            maybeCurrentModel
                                                                |> Maybe.withDefault wrappedModel

                                                        fetcherResult =
                                                            case actionResult of
                                                                RenderPage _ actionData ->
                                                                    Ok ( Nothing, Platform.ActionResponse (Just actionData) )

                                                                ServerResponse serverResponse ->
                                                                    case PageServerResponse.toRedirect serverResponse of
                                                                        Just { location } ->
                                                                            Ok ( Nothing, Platform.RedirectResponse location )

                                                                        Nothing ->
                                                                            Ok ( Nothing, Platform.ActionResponse Nothing )

                                                                ErrorPage _ _ ->
                                                                    Ok ( Nothing, Platform.ActionResponse Nothing )

                                                        updatedJar =
                                                            case actionResult of
                                                                ServerResponse serverResponse ->
                                                                    effectiveModel.cookieJar
                                                                        |> CookieJar.applySetCookieHeaders
                                                                            (extractSetCookieHeaders (ServerResponse serverResponse))

                                                                _ ->
                                                                    effectiveModel.cookieJar

                                                        -- Dispatch FetcherComplete to the effective model
                                                        -- (current when available, stale as fallback).
                                                        ( modelAfterComplete, completeEffect ) =
                                                            platformUpdateClean config
                                                                (Platform.FetcherComplete False fetcherKey transitionId fetcherResult)
                                                                effectiveModel.platformModel

                                                        ( processedWrapped2, _, _ ) =
                                                            processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                                                { platformModel = modelAfterComplete, virtualFs = effectiveModel.virtualFs, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                                                completeEffect
                                                                100
                                                    in
                                                    case processedWrapped2.pendingDataError of
                                                        Just _ ->
                                                            -- Data reload needs HTTP. Delegate to makePlatformResolver.
                                                            Advanced (makePlatformResolver config baseUrl processedWrapped2 makeReady)

                                                        Nothing ->
                                                            Advanced (Ready (makeReady processedWrapped2))

                                                Err errMsg ->
                                                    AdvanceError ("Fetcher action resolution failed:\n\n" ++ errMsg)
                                    , pendingDescription =
                                        stillRunningDescription runningState.pendingRequests
                                    , pendingUrls =
                                        List.map .url runningState.pendingRequests
                                    }
                        in
                        ( { wrappedModel
                            | platformModel = modelAfterStarted
                            , virtualFs = vfsAfterAction
                          }
                        , []
                        , [ fetcherResolver ]
                        )

                    BackendTaskTest.TestError errMsg ->
                        ( { wrappedModel
                            | platformModel = modelAfterStarted
                            , virtualFs = vfsAfterAction
                            , pendingDataError = Just ("Route action (fetcher) BackendTask error: " ++ errMsg)
                          }
                        , []
                        , []
                        )

                    BackendTaskTest.Done doneState ->
                        let
                            actionResult =
                                doneState.result

                            -- Capture Set-Cookie headers from the action response
                            updatedJar =
                                case actionResult of
                                    Ok response ->
                                        wrappedModel.cookieJar
                                            |> CookieJar.applySetCookieHeaders
                                                (extractSetCookieHeaders response)

                                    Err _ ->
                                        wrappedModel.cookieJar

                            -- Step 3: Dispatch FetcherComplete
                            fetcherResult =
                                case actionResult of
                                    Ok (RenderPage _ actionData) ->
                                        Ok ( Nothing, Platform.ActionResponse (Just actionData) )

                                    Ok (ServerResponse serverResponse) ->
                                        case PageServerResponse.toRedirect serverResponse of
                                            Just { location } ->
                                                Ok ( Nothing, Platform.RedirectResponse location )

                                            Nothing ->
                                                Ok ( Nothing, Platform.ActionResponse Nothing )

                                    Ok (PageServerResponse.ErrorPage _ _) ->
                                        Ok ( Nothing, Platform.ActionResponse Nothing )

                                    Err _ ->
                                        Err Http.NetworkError

                            ( modelAfterComplete, completeEffect ) =
                                platformUpdateClean config
                                    (Platform.FetcherComplete False fetcherKey transitionId fetcherResult)
                                    modelAfterStarted
                        in
                        processEffectsWrapped config baseUrl makeReady makePlatformResolver
                            { platformModel = modelAfterComplete, virtualFs = vfsAfterAction, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                            completeEffect
                            (maxDepth - 1)

            Platform.Batch effects ->
                List.foldl
                    (\eff ( wm, effs, resolvers ) ->
                        let
                            ( newWm, newEffs, newResolvers ) =
                                processEffectsWrapped config baseUrl makeReady makePlatformResolver wm eff (maxDepth - 1)
                        in
                        ( newWm, effs ++ newEffs, resolvers ++ newResolvers )
                    )
                    ( wrappedModel, [], [] )
                    effects


{-| Wrapper around Platform.update that cleans relative path segments
from the resulting model's URL. Platform internally produces paths like
"/./counter" during redirect handling which breaks route matching.
-}
platformUpdateClean config msg platformModel =
    let
        -- Normalize the model's URL path BEFORE calling Platform.update.
        -- This ensures that internal handlers like startNewGetLoad use
        -- the clean path (e.g. "/" instead of ".") for route matching.
        cleanUrl u =
            { u | path = normalizePath u.path }

        cleanedInput =
            { platformModel
                | url = cleanUrl platformModel.url
                , currentPath = normalizePath platformModel.currentPath
                , pendingFrozenViewsUrl =
                    platformModel.pendingFrozenViewsUrl
                        |> Maybe.map cleanUrl
            }

        ( newModel, effect ) =
            Platform.update config msg cleanedInput
    in
    ( { newModel
        | url = cleanUrl newModel.url
        , currentPath = normalizePath newModel.currentPath
        , pendingFrozenViewsUrl =
            newModel.pendingFrozenViewsUrl
                |> Maybe.map cleanUrl
      }
    , effect
    )


makeTestUrl : String -> String -> Url
makeTestUrl baseUrl rawPath =
    let
        -- Clean relative path segments that Platform may produce
        -- during redirect handling (e.g., "/./counter" -> "/counter",
        -- "./counter" -> "/counter")
        path =
            rawPath
                |> String.replace "/./" "/"
                |> (\p ->
                        if String.startsWith "./" p then
                            "/" ++ String.dropLeft 2 p

                        else
                            p
                   )

        fullUrl =
            if String.startsWith "http" path then
                path

            else
                baseUrl ++ path
    in
    case Url.fromString fullUrl of
        Just url ->
            url

        Nothing ->
            -- Fallback: construct URL manually
            { protocol = Url.Https
            , host = "localhost"
            , port_ = Just 1234
            , path = path
            , query = Nothing
            , fragment = Nothing
            }


{-| Extract Set-Cookie header values from a PageServerResponse.
-}
extractSetCookieHeaders : PageServerResponse data error -> List String
extractSetCookieHeaders response =
    let
        filterSetCookie headers =
            headers
                |> List.filter (\( name, _ ) -> String.toLower name == "set-cookie")
                |> List.map Tuple.second
    in
    case response of
        RenderPage { headers } _ ->
            filterSetCookie headers

        ServerResponse serverResponse ->
            filterSetCookie serverResponse.headers

        PageServerResponse.ErrorPage _ _ ->
            []


platformTestRequest : String -> CookieJar -> Internal.Request.Request
platformTestRequest url cookieJar =
    Internal.Request.Request
        { time = Time.millisToPosix 0
        , method = "GET"
        , body = Nothing
        , rawUrl = url
        , rawHeaders = Dict.empty
        , cookies = CookieJar.toDict cookieJar
        }


{-| Encode a ResponseSketch with the frozen views prefix that decodeResponse
expects. The prefix is a 4-byte big-endian length (0) indicating zero bytes
of frozen view data to skip.
-}
encodeResponseWithPrefix config sketch =
    Bytes.Encode.encode
        (Bytes.Encode.sequence
            [ Bytes.Encode.unsignedInt32 Bytes.BE 0
            , config.encodeResponse sketch
            ]
        )


resultErrorToString : Result String a -> String
resultErrorToString result =
    case result of
        Err msg ->
            msg

        Ok _ ->
            ""


encodeFormFields : List ( String, String ) -> String
encodeFormFields fields =
    fields
        |> List.map
            (\( name, value ) ->
                Url.percentEncode name ++ "=" ++ Url.percentEncode value
            )
        |> String.join "&"


{-| Extract page data from a PageServerResponse result, converting ErrorPage
responses to page data using config.errorPageToData (matching server behavior).
-}
extractPageData config result =
    case result of
        Ok (RenderPage _ pageData) ->
            Just pageData

        Ok (PageServerResponse.ErrorPage errorPage _) ->
            Just (config.errorPageToData errorPage)

        _ ->
            Nothing


{-| Normalize paths produced by Platform during redirect handling.
Handles:
  - "/./counter" -> "/counter"  (relative path segments)
  - "./" -> "/"  (base URL "." relative)
  - "/." -> "/"  (base URL "." absolute)
  - "." -> "/"   (bare dot)
-}
normalizePath : String -> String
normalizePath path =
    path
        |> String.replace "/./" "/"
        |> (\p ->
                if p == "." || p == "/." || p == "./" then
                    "/"

                else if String.startsWith "./" p then
                    "/" ++ String.dropLeft 2 p

                else
                    p
           )


nonEmpty : String -> String -> String
nonEmpty default value =
    if String.isEmpty value then
        default

    else
        value


fatalErrorToString : FatalError -> String
fatalErrorToString err =
    case err of
        Pages.Internal.FatalError.FatalError info ->
            info.title ++ ": " ++ info.body


{-| Apply a Simulation to a BackendTaskTest. Used in the platform pause-and-resume
path when simulating HTTP responses for data that paused on navigation.
-}
applySimToBt : Simulation -> BackendTaskTest.BackendTaskTest a -> BackendTaskTest.BackendTaskTest a
applySimToBt sim bt =
    case sim of
        SimHttpGet url resp ->
            BackendTaskTest.simulateHttpGet url resp bt

        SimHttpPost url resp ->
            BackendTaskTest.simulateHttpPost url resp bt

        SimHttpError method url errorString ->
            BackendTaskTest.simulateHttpError method url errorString bt

        SimCustom portName resp ->
            BackendTaskTest.simulateCustom portName resp bt


{-| Extract pending HTTP URLs from a BackendTaskTest. Used to populate
the Resolver's pendingUrls field for URL-targeted simulation.
-}
btPendingUrls : BackendTaskTest.BackendTaskTest a -> List String
btPendingUrls bt =
    case bt of
        BackendTaskTest.Running runningState ->
            List.map .url runningState.pendingRequests

        _ ->
            []


{-| Handle the result of advancing an action BackendTaskTest after simulation.
When Done, processes the action result (redirect, render, etc).
When Running, creates a Resolver capturing the BackendTaskTest for subsequent sims.
-}
continueActionWithBt config baseUrl makeReady makePlatformResolver continueDataWithBt wrappedModel fetchUrl makePhase bt =
    let
        vfsAfterAction =
            BackendTaskTest.extractVirtualFs bt

        route =
            config.urlToRoute fetchUrl
    in
    case bt of
        BackendTaskTest.Done doneState ->
            case doneState.result of
                Ok (ServerResponse serverResponse) ->
                    let
                        updatedJar =
                            wrappedModel.cookieJar
                                |> CookieJar.applySetCookieHeaders
                                    (extractSetCookieHeaders (ServerResponse serverResponse))
                    in
                    case PageServerResponse.toRedirect serverResponse of
                        Just { location } ->
                            let
                                cleanLocation =
                                    normalizePath location

                                encodedBytes =
                                    ResponseSketch.Redirect cleanLocation
                                        |> encodeResponseWithPrefix config

                                ( newModel, newEffect ) =
                                    platformUpdateClean config
                                        (Platform.FrozenViewsReady (Just encodedBytes))
                                        wrappedModel.platformModel

                                ( processedWrapped, _, _ ) =
                                    processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                        { platformModel = newModel, virtualFs = vfsAfterAction, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                        newEffect
                                        100
                            in
                            -- If the redirect target's data also needs HTTP, create
                            -- a Resolver for it instead of returning Ready.
                            case processedWrapped.pendingDataPath of
                                Just dataPath ->
                                    let
                                        dataFetchUrl =
                                            makeTestUrl baseUrl dataPath

                                        dataRoute =
                                            config.urlToRoute dataFetchUrl

                                        ( _, dataBt ) =
                                            BackendTaskTest.resolveWithVirtualFsPartial
                                                processedWrapped.virtualFs
                                                (config.data (platformTestRequest (Url.toString dataFetchUrl) processedWrapped.cookieJar) dataRoute)

                                        dataMakePhase m =
                                            makePhase m
                                    in
                                    Advanced
                                        (Resolving
                                            (Resolver
                                                { advance =
                                                    \_ sim ->
                                                        continueDataWithBt processedWrapped dataMakePhase (applySimToBt sim dataBt)
                                                , pendingDescription =
                                                    processedWrapped.pendingDataError |> Maybe.withDefault "Pending data HTTP after action redirect"
                                                , pendingUrls = btPendingUrls dataBt
                                                }
                                            )
                                        )

                                Nothing ->
                                    Advanced (makePhase processedWrapped)

                        Nothing ->
                            Advanced (makePhase { wrappedModel | virtualFs = vfsAfterAction, cookieJar = updatedJar, pendingActionBody = Nothing })

                Ok ((RenderPage _ actionData) as renderResponse) ->
                    let
                        updatedJar =
                            wrappedModel.cookieJar
                                |> CookieJar.applySetCookieHeaders
                                    (extractSetCookieHeaders renderResponse)

                        ( vfsAfterData, dataResult ) =
                            BackendTaskTest.resolveWithVirtualFs
                                vfsAfterAction
                                (config.data (platformTestRequest (Url.toString fetchUrl) updatedJar) route)
                    in
                    case extractPageData config dataResult of
                        Just pageData ->
                            let
                                encodedBytes =
                                    ResponseSketch.RenderPage pageData (Just actionData)
                                        |> encodeResponseWithPrefix config

                                ( newModel, newEffect ) =
                                    platformUpdateClean config
                                        (Platform.FrozenViewsReady (Just encodedBytes))
                                        wrappedModel.platformModel

                                ( processedWrapped, _, _ ) =
                                    processEffectsWrapped config baseUrl makeReady makePlatformResolver
                                        { platformModel = newModel, virtualFs = vfsAfterData, cookieJar = updatedJar, pendingDataError = Nothing, pendingDataPath = Nothing, pendingActionBody = Nothing}
                                        newEffect
                                        100
                            in
                            Advanced (makePhase processedWrapped)

                        Nothing ->
                            -- Data after action needs HTTP. Create a data Resolver.
                            let
                                dataPath =
                                    normalizePath (Url.toString fetchUrl)

                                -- Ensure pendingFrozenViewsUrl is set so the platform's
                                -- FrozenViewsReady handler processes the data correctly
                                -- (without it, RenderPage/HotUpdate gets discarded).
                                platformModelWithPendingUrl =
                                    let
                                        pm = wrappedModel.platformModel
                                    in
                                    { pm | pendingFrozenViewsUrl = Just fetchUrl }

                                updatedModel =
                                    { wrappedModel
                                        | virtualFs = vfsAfterData
                                        , cookieJar = updatedJar
                                        , platformModel = platformModelWithPendingUrl
                                        , pendingDataError =
                                            Just ("Route data has a pending BackendTask that needs a simulated response:\n\n" ++ resultErrorToString dataResult)
                                        , pendingDataPath = Just dataPath
                                    }

                                ( _, dataBt ) =
                                    BackendTaskTest.resolveWithVirtualFsPartial
                                        vfsAfterData
                                        (config.data (platformTestRequest (Url.toString fetchUrl) updatedJar) route)

                            in
                            Advanced
                                (Resolving
                                    (Resolver
                                        { advance =
                                            \_ sim2 ->
                                                continueDataWithBt updatedModel makePhase (applySimToBt sim2 dataBt)
                                        , pendingDescription =
                                            "Pending data HTTP after action"
                                        , pendingUrls = btPendingUrls dataBt
                                        }
                                    )
                                )

                Err fatalErr ->
                    let
                        (Pages.Internal.FatalError.FatalError errInfo) =
                            fatalErr
                    in
                    AdvanceError ("Route action failed: " ++ errInfo.title ++ ": " ++ errInfo.body)

                _ ->
                    Advanced (makePhase { wrappedModel | virtualFs = vfsAfterAction, pendingActionBody = Nothing })

        BackendTaskTest.Running runningState ->
            Advanced
                (Resolving
                    (Resolver
                        { advance =
                            \_ sim ->
                                continueActionWithBt config baseUrl makeReady makePlatformResolver continueDataWithBt wrappedModel fetchUrl makePhase (applySimToBt sim bt)
                        , pendingDescription =
                            stillRunningDescription runningState.pendingRequests
                        , pendingUrls =
                            List.map .url runningState.pendingRequests
                        }
                    )
                )

        BackendTaskTest.TestError errMsg ->
            AdvanceError errMsg
