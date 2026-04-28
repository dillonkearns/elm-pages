module Test.PagesProgram.Internal exposing
    ( Snapshot, StepKind(..), TargetSelector(..), NetworkEntry, NetworkStatus(..), FetcherEntry, FetcherStatus(..), AssertionSelector(..)
    , ProgramTest(..), State, Phase(..), ReadyState, Resolver(..), ResolverKind(..), Simulation(..), AdvanceResult(..)
    , initialProgramTest, initialProgramTestWithEffects
    , resolveDataPhase, mapViewToSnapshot, describeEffects, describeHttpRequest
    , unsafeCoerceHtmlList, crashNever
    , stillRunningDescription, requestDetailsFromRequests, requestToDetails, bodyToString
    , NetworkSource(..), fetcherToFormData, unsupportedPlatformEffectError
    , done, toSnapshots
    , Step(..)
    , withinFindImpl, groupImpl
    )

{-| Internal types used by the visual test runner (Viewer) and the
framework's own test suite. These are not part of the public API and
should not be relied upon by end users.

@docs Snapshot, StepKind, TargetSelector, NetworkEntry, NetworkStatus, FetcherEntry, FetcherStatus, AssertionSelector
@docs ProgramTest, State, Phase, ReadyState, Resolver, ResolverKind, Simulation, AdvanceResult
@docs initialProgramTest, initialProgramTestWithEffects
@docs resolveDataPhase, mapViewToSnapshot, describeEffects, describeHttpRequest
@docs unsafeCoerceHtmlList, crashNever
@docs stillRunningDescription, requestDetailsFromRequests, requestToDetails, bodyToString
@docs done, toSnapshots
@docs Step
@docs withinFindImpl, groupImpl

-}

import BackendTask exposing (BackendTask)
import Expect
import FatalError exposing (FatalError)
import Form
import Html exposing (Html)
import Json.Encode as Encode
import Pages.Fetcher
import Pages.Internal.FatalError
import Pages.Internal.Platform as Platform
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.StaticHttp.Request as StaticHttpRequest
import Test.BackendTask.Internal as BackendTaskTest
import Test.Html.Query as Query
import Test.Html.Selector
import Test.PagesProgram.CookieJar as CookieJar exposing (CookieEntry)
import Test.PagesProgram.SimulatedSub exposing (SimulatedSub)


{-| Structured selector data used by the visual runner to highlight matching
elements. Derived from the label string produced by `Query.has`'s
failure description.
-}
type AssertionSelector
    = ByText String
    | ByClass String
    | ById_ String
    | ByTag_ String
    | ByValue String
    | ByContaining (List AssertionSelector)
    | ByOther String


{-| A snapshot of the program state at a point in the test pipeline.
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
    , assertionSelectors : List AssertionSelector
    , scopeSelectors : List (List AssertionSelector)
    , fetcherLog : List FetcherEntry
    , cookieLog : List ( String, CookieEntry )
    , groupLabel : Maybe String
    , representative : Bool
    }


{-| The kind of step that produced a snapshot.
-}
type StepKind
    = Start
    | Interaction
    | Assertion
    | EffectResolution
    | Error


{-| An HTTP request or custom port entry in the network log.
-}
type alias NetworkEntry =
    { method : String
    , url : String
    , status : NetworkStatus
    , stepIndex : Int
    , portName : Maybe String
    , responsePreview : Maybe String
    , source : NetworkSource
    , requestBody : Maybe String
    , requestHeaders : List ( String, String )
    }


{-| Whether an HTTP request is pending, completed, or failed.
-}
type NetworkStatus
    = Stubbed
    | Failed
    | Pending


{-| Whether the request originated from a BackendTask (server-side) or
from a client-side TEA Effect.
-}
type NetworkSource
    = Backend
    | Frontend


{-| Describes which DOM element a test interaction targeted.
-}
type TargetSelector
    = ByTagAndText String String
    | ByFormField String String
    | ByLabelText String
    | ById String
    | ByTag String
    | BySelectors (List AssertionSelector)


{-| A snapshot of an in-flight fetcher's state.
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



-- CORE TEST TYPES


{-| An in-progress elm-pages program test.
-}
type ProgramTest model msg
    = ProgramTest (State model msg)


{-| Mutable-feeling state threaded through a test pipeline.
-}
type alias State model msg =
    { phase : Phase model msg
    , error : Maybe String
    , snapshots : List Snapshot
    , modelToString : Maybe (model -> String)
    , fetcherExtractor : Maybe (model -> List FetcherEntry)
    , cookieExtractor : Maybe (model -> List ( String, CookieEntry ))
    , pendingFetcherEffects : List (Resolver model msg)
    , lastReadyModel : Maybe model
    , networkLog : List NetworkEntry
    , subscriptions : Maybe (model -> SimulatedSub msg)
    }


{-| The current phase of a test pipeline: still resolving initial data, or
ready and interactable.
-}
type Phase model msg
    = Resolving (Resolver model msg)
    | Ready (ReadyState model msg)


{-| Origin of a resolver, used for network log classification.
-}
type ResolverKind
    = BackendResolver
    | FetcherResolver
    | BackgroundReloadResolver


{-| Hides the `data` type parameter behind closures so `ProgramTest` only
needs `model` and `msg` type parameters.
-}
type Resolver model msg
    = Resolver
        { kind : ResolverKind
        , advance : Maybe model -> Simulation -> AdvanceResult model msg
        , pendingDescription : String
        , pendingUrls : List String
        , pendingRequestDetails : List { url : String, method : String, headers : List ( String, String ), body : Maybe String }
        }


{-| A request to resolve some pending external effect (HTTP, custom port).
-}
type Simulation
    = SimHttpGet String Encode.Value
    | SimHttpPost String Encode.Value
    | SimHttpError String String String
    | SimCustom String Encode.Value


unsupportedPlatformEffectError : Platform.Effect userMsg pageData actionData sharedData userEffect errorPage -> Maybe String
unsupportedPlatformEffectError effect =
    case effect of
        Platform.RunCmd _ ->
            Just "Test.PagesProgram cannot simulate Platform.RunCmd. Convert application Cmd values to Test.PagesProgram.SimulatedEffect values so the test can resolve or explicitly ignore them."

        Platform.BrowserLoadUrl url ->
            Just ("Test.PagesProgram cannot simulate Platform.BrowserLoadUrl for external URL \"" ++ url ++ "\". Assert on internal navigation with expectBrowserUrl, or model this external load as an explicit user effect.")

        _ ->
            Nothing


fetcherToFormData : String -> Pages.Fetcher.Fetcher msg -> { fields : List ( String, String ), method : Form.Method, action : String, id : Maybe String }
fetcherToFormData currentPath (Pages.Fetcher.Fetcher fetcher) =
    { fields = fetcher.fields
    , method = Form.Post
    , action = fetcher.url |> Maybe.withDefault currentPath
    , id = Nothing
    }


{-| Outcome of advancing a resolver with a `Simulation`.
-}
type AdvanceResult model msg
    = Advanced (Phase model msg) (Maybe model) (List (Resolver model msg))
    | AdvanceError String


{-| Full state of a test that's ready for interaction.
-}
type alias ReadyState model msg =
    { model : model
    , getView : model -> { title : String, body : List (Html msg) }
    , update : msg -> model -> { model : model, effects : List (BackendTask FatalError msg), pendingPhase : Maybe (Phase model msg), fetcherResolvers : List (Resolver model msg) }
    , pendingEffects : List (BackendTask FatalError msg)
    , onNavigate : Maybe (String -> msg)
    , getBrowserUrl : Maybe (model -> String)
    , onFormSubmit : Maybe ({ formId : String, action : String, fields : List ( String, String ), method : Form.Method, useFetcher : Bool } -> msg)
    , getFormFields : Maybe (model -> List ( String, String ))
    , viewScope : Query.Single msg -> Query.Single msg
    , scopeLabels : List String
    , scopeSelectors : List (List AssertionSelector)
    , getModelError : model -> Maybe String
    }



-- LIGHTWEIGHT HARNESS


{-| Build an initial `ProgramTest` from a lightweight
`(data, init, update, view)` config. Used by the framework's own test
suite to exercise `Test.PagesProgram`'s behavior without constructing
a full `Main.config`. Application code should use
[`Test.PagesProgram.start`](Test-PagesProgram#start) instead.
-}
initialProgramTest :
    { data : BackendTask FatalError data
    , init : data -> ( model, List (BackendTask FatalError msg) )
    , update : msg -> model -> ( model, List (BackendTask FatalError msg) )
    , view : data -> model -> { title : String, body : List (Html msg) }
    }
    -> ProgramTest model msg
initialProgramTest config =
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
                      , assertionSelectors = []
                      , scopeSelectors = []
                      , fetcherLog = []
                      , cookieLog = []
                      , groupLabel = Nothing
                      , representative = False
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
                      , assertionSelectors = []
                      , scopeSelectors = []
                      , fetcherLog = []
                      , cookieLog = []
                      , groupLabel = Nothing
                      , representative = False
                      }
                    ]
    in
    ProgramTest
        { phase = phase
        , error = Nothing
        , snapshots = initSnapshot
        , modelToString = Nothing
        , fetcherExtractor = Nothing
        , cookieExtractor = Nothing
        , pendingFetcherEffects = []
        , lastReadyModel = Nothing
        , networkLog = []
        , subscriptions = Nothing
        }


{-| Like [`initialProgramTest`](#initialProgramTest), but for programs
that use a custom `Effect` type. Provide a function that converts your
`Effect` into a list of `BackendTask`s the framework can simulate.
-}
initialProgramTestWithEffects :
    (effect -> List (BackendTask FatalError msg))
    ->
        { data : BackendTask FatalError data
        , init : data -> ( model, effect )
        , update : msg -> model -> ( model, effect )
        , view : data -> model -> { title : String, body : List (Html msg) }
        }
    -> ProgramTest model msg
initialProgramTestWithEffects extractEffects config =
    initialProgramTest
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



-- HELPER FUNCTIONS


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


{-| Render a single HTTP request as `METHOD url` for effect descriptions.
-}
describeHttpRequest : StaticHttpRequest.Request -> String
describeHttpRequest req =
    req.method ++ " " ++ req.url


{-| Coerce a user view's `Html msg` to `Html Never` so the snapshot
viewer can render it without triggering user messages.
-}
mapViewToSnapshot : { title : String, body : List (Html msg) } -> { title : String, body : List (Html Never) }
mapViewToSnapshot v =
    -- We store body as Html Never for the snapshot viewer (non-interactive).
    -- This is safe because the viewer maps all events to NoOp anyway.
    { title = v.title, body = unsafeCoerceHtmlList v.body }


{-| The phantom-msg-parameter `Html` type trick. Same technique
elm-explorations/test uses internally.
-}
unsafeCoerceHtmlList : List (Html a) -> List (Html b)
unsafeCoerceHtmlList =
    -- elm-explorations/test uses the same trick internally.
    -- Html is a virtual-dom node; the msg type param is phantom.
    List.map (Html.map (\_ -> crashNever ()))


{-| Unreachable tag-remapper used by [`unsafeCoerceHtmlList`](#unsafeCoerceHtmlList).
Never actually invoked because the viewer maps events to NoOp before
they'd reach the original Html msg tagger.
-}
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
                        , update =
                            \msg m ->
                                let
                                    ( m2, effs ) =
                                        updateFn msg m
                                in
                                { model = m2, effects = effs, pendingPhase = Nothing, fetcherResolvers = [] }
                        , pendingEffects = effects
                        , onNavigate = Nothing
                        , getBrowserUrl = Nothing
                        , onFormSubmit = Nothing
                        , getFormFields = Nothing
                        , viewScope = identity
                        , scopeLabels = []
                        , scopeSelectors = []
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
                            { kind = BackendResolver
                            , advance = \_ _ -> AdvanceError (errInfo.title ++ ": " ++ errInfo.body)
                            , pendingDescription =
                                "Data BackendTask failed with FatalError:\n\n"
                                    ++ errInfo.title
                                    ++ "\n"
                                    ++ errInfo.body
                            , pendingUrls = []
                            , pendingRequestDetails = []
                            }
                        )

        BackendTaskTest.Running runningState ->
            Resolving
                (Resolver
                    { kind = BackendResolver
                    , advance =
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
                            Advanced (resolveDataPhase newBt initFn viewFn updateFn) Nothing []
                    , pendingDescription =
                        stillRunningDescription runningState.pendingRequests
                    , pendingUrls =
                        List.map .url runningState.pendingRequests
                    , pendingRequestDetails =
                        requestDetailsFromRequests runningState.pendingRequests
                    }
                )

        BackendTaskTest.TestError msg ->
            Resolving
                (Resolver
                    { kind = BackendResolver
                    , advance = \_ _ -> AdvanceError msg
                    , pendingDescription = msg
                    , pendingUrls = []
                    , pendingRequestDetails = []
                    }
                )


{-| Describe a list of pending BackendTask URLs as a human-readable message.
-}
stillRunningDescription : List { a | url : String } -> String
stillRunningDescription pendingRequests =
    "Pending requests:\n\n"
        ++ (pendingRequests
                |> List.map (\req -> "    " ++ req.url)
                |> String.join "\n"
           )


{-| Convert a `StaticHttpRequest.Request` to the simplified details used for network display.
-}
requestToDetails : StaticHttpRequest.Request -> { url : String, method : String, headers : List ( String, String ), body : Maybe String }
requestToDetails req =
    { url = req.url
    , method = req.method
    , headers = req.headers
    , body = bodyToString req.body
    }


{-| Map a list of `StaticHttpRequest.Request`s to their display-friendly details.
-}
requestDetailsFromRequests : List StaticHttpRequest.Request -> List { url : String, method : String, headers : List ( String, String ), body : Maybe String }
requestDetailsFromRequests =
    List.map requestToDetails


{-| Serialize a request body to a string for display in the network panel.
-}
bodyToString : StaticHttpBody.Body -> Maybe String
bodyToString body =
    case body of
        StaticHttpBody.EmptyBody ->
            Nothing

        StaticHttpBody.JsonBody value ->
            Just (Encode.encode 2 value)

        StaticHttpBody.StringBody _ content ->
            Just content

        StaticHttpBody.BytesBody _ _ ->
            Just "<binary data>"

        StaticHttpBody.MultipartBody _ _ ->
            Just "<multipart data>"


{-| Internal: finalize a `ProgramTest` to an `Expect.Expectation`.

Public callers go through `Test.PagesProgram.test` or
`Test.PagesProgram.expect`. Exposed here so the framework's own meta
tests can finalize chained `ProgramTest` values directly without
threading them through a `List Step`.
-}
done : ProgramTest model msg -> Expect.Expectation
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
                    let
                        modelError =
                            ready.getModelError ready.model

                        pendingEffectDescriptions =
                            describeEffects ready.pendingEffects

                        pendingFetcherDescriptions =
                            state.pendingFetcherEffects
                                |> List.map
                                    (\(Resolver resolver) ->
                                        resolver.pendingDescription
                                    )

                        allPendingDescriptions =
                            pendingEffectDescriptions ++ pendingFetcherDescriptions

                        pendingCount =
                            List.length ready.pendingEffects + List.length state.pendingFetcherEffects
                    in
                    case modelError of
                        Just errMsg ->
                            Expect.fail errMsg

                        Nothing ->
                            if pendingCount == 0 then
                                Expect.pass

                            else
                                let
                                    descriptionText =
                                        if List.isEmpty allPendingDescriptions then
                                            ""

                                        else
                                            "\n\nPending:\n"
                                                ++ (allPendingDescriptions
                                                        |> List.map (\d -> "  - " ++ d)
                                                        |> String.join "\n"
                                                   )
                                in
                                Expect.fail
                                    ("There are "
                                        ++ String.fromInt pendingCount
                                        ++ " pending BackendTask effect(s) or fetcher resolution(s) that must be resolved before ending the test."
                                        ++ descriptionText
                                    )


{-| Internal: extract recorded snapshots from a `ProgramTest`. If the
pipeline encountered an error that wasn't already captured inline on a
recorded snapshot (e.g., a framework-level error during data
resolution), append a synthetic error snapshot so the viewer has
something to display. Assertion failures are recorded inline by their
own impls (see `recordFailedAssertionSnapshot`) so we don't double-up.
-}
toSnapshots : ProgramTest model msg -> List Snapshot
toSnapshots (ProgramTest state) =
    case state.error of
        Just errorMsg ->
            let
                lastHasError : Bool
                lastHasError =
                    state.snapshots
                        |> List.reverse
                        |> List.head
                        |> Maybe.map (\s -> s.errorMessage /= Nothing)
                        |> Maybe.withDefault False
            in
            if lastHasError then
                state.snapshots

            else
                let
                    latestCookieLog : List ( String, CookieJar.CookieEntry )
                    latestCookieLog =
                        state.snapshots
                            |> List.reverse
                            |> List.head
                            |> Maybe.map .cookieLog
                            |> Maybe.withDefault []
                in
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
                         , assertionSelectors = []
                         , scopeSelectors = []
                         , fetcherLog = []
                         , cookieLog = latestCookieLog
                         , groupLabel = Nothing
                         , representative = False
                         }
                       ]

        Nothing ->
            state.snapshots


{-| Internal: opaque step value. The constructor is exposed at the
Internal level so `Test.PagesProgram` can build and unwrap `Step`
values when assembling pipelines. End-user code only sees
`Test.PagesProgram.Step` (the type alias) and never constructs or
pattern-matches on it.
-}
type Step model msg
    = Step (ProgramTest model msg -> ProgramTest model msg)


{-| Internal: chainable `withinFind` implementation. Takes a closure
mapping `ProgramTest -> ProgramTest`. Pre-computed `assertionSels` and
`label` are passed in so this module doesn't have to depend on
`Test.PagesProgram.SelectorLabel` (which depends on Internal).
-}
withinFindImpl : List Test.Html.Selector.Selector -> List AssertionSelector -> String -> (ProgramTest model msg -> ProgramTest model msg) -> ProgramTest model msg -> ProgramTest model msg
withinFindImpl selectors assertionSels label action (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest state

                Ready ready ->
                    let
                        scopedReady =
                            { ready
                                | viewScope = ready.viewScope >> Query.find selectors
                                , scopeLabels = ready.scopeLabels ++ [ label ]
                                , scopeSelectors = ready.scopeSelectors ++ [ assertionSels ]
                            }

                        scopedState =
                            { state | phase = Ready scopedReady }

                        (ProgramTest resultState) =
                            action (ProgramTest scopedState)
                    in
                    ProgramTest
                        { resultState
                            | phase =
                                case resultState.phase of
                                    Ready resultReady ->
                                        Ready { resultReady | viewScope = ready.viewScope, scopeLabels = ready.scopeLabels, scopeSelectors = ready.scopeSelectors }

                                    other ->
                                        other
                        }


{-| Internal: chainable `group` implementation.
-}
groupImpl : String -> (ProgramTest model msg -> ProgramTest model msg) -> ProgramTest model msg -> ProgramTest model msg
groupImpl name pipeline (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            let
                startIndex =
                    List.length state.snapshots

                (ProgramTest innerState) =
                    pipeline (ProgramTest state)

                updatedSnapshots =
                    innerState.snapshots
                        |> List.indexedMap
                            (\i snap ->
                                if i >= startIndex then
                                    { snap | groupLabel = Just name }

                                else
                                    snap
                            )
            in
            ProgramTest { innerState | snapshots = updatedSnapshots }
